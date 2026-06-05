import Foundation

struct AgentEventLogReader {
    private static let readByteLimit: UInt64 = 384 * 1024

    let paths: CodexPaths
    let provider: AgentProvider
    let supportedEventTypes: Set<String>?
    let duplicateWindows: [String: TimeInterval]
    let defaultDuplicateWindow: TimeInterval
    private let fileManager: FileManager

    init(
        paths: CodexPaths = CodexPaths(),
        provider: AgentProvider,
        supportedEventTypes: Set<String>? = nil,
        duplicateWindows: [String: TimeInterval] = [:],
        defaultDuplicateWindow: TimeInterval = 2,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.provider = provider
        self.supportedEventTypes = supportedEventTypes
        self.duplicateWindows = duplicateWindows
        self.defaultDuplicateWindow = defaultDuplicateWindow
        self.fileManager = fileManager
    }

    func readRecentEvents(limit: Int) -> [AgentEvent] {
        let events = eventLogURLs()
            .flatMap(readEvents)
            .sorted { $0.timestamp > $1.timestamp }

        var recentEvents: [AgentEvent] = []
        for event in events {
            guard recentEvents.count < limit else { break }
            if recentEvents.last.map({ isDuplicate(event, of: $0) }) == true {
                continue
            }
            recentEvents.append(event)
        }
        return recentEvents
    }

    private func readEvents(from url: URL) -> [AgentEvent] {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let fileSize = try handle.seekToEnd()
            let offset = fileSize > Self.readByteLimit ? fileSize - Self.readByteLimit : 0
            try handle.seek(toOffset: offset)
            guard var data = try handle.readToEnd() else { return [] }

            if offset > 0 {
                guard let firstNewline = data.firstIndex(of: 0x0A) else { return [] }
                data.removeSubrange(data.startIndex...firstNewline)
            }

            guard let content = String(data: data, encoding: .utf8) else { return [] }
            return content
                .split(separator: "\n")
                .compactMap { AgentEvent.decodeLossyJSONLine(String($0)) }
                .filter(isSupported)
        } catch {
            return []
        }
    }

    private func eventLogURLs() -> [URL] {
        guard let eventFiles = try? fileManager.contentsOfDirectory(
            at: paths.providerDirectory(provider: provider),
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return eventFiles.filter { $0.pathExtension == "jsonl" }
    }

    private func isSupported(_ event: AgentEvent) -> Bool {
        guard event.provider == provider else { return false }
        guard let supportedEventTypes else { return true }
        return supportedEventTypes.contains(event.type)
    }

    private func isDuplicate(_ event: AgentEvent, of previousEvent: AgentEvent) -> Bool {
        event.provider == previousEvent.provider
            && event.type == previousEvent.type
            && event.threadID == previousEvent.threadID
            && event.toolName == previousEvent.toolName
            && event.detail == previousEvent.detail
            && event.message == previousEvent.message
            && abs(event.timestamp.timeIntervalSince(previousEvent.timestamp)) <= duplicateWindow(for: event)
    }

    private func duplicateWindow(for event: AgentEvent) -> TimeInterval {
        duplicateWindows[event.type] ?? defaultDuplicateWindow
    }
}
