import Darwin
import Foundation

struct CodexHookWriter {
    struct LatestState: Codable {
        let provider: AgentProvider
        let activityStatus: AgentEvent.Status
        let lastEvent: AgentEvent
    }

    let paths: CodexPaths
    private let fileManager: FileManager

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func write(eventType: String, stdinData: Data) throws {
        try fileManager.createDirectory(at: paths.floatMonDirectory, withIntermediateDirectories: true)
        let metadata = Self.metadata(from: stdinData)
        let event = AgentEvent(
            provider: .codex,
            type: eventType,
            timestamp: Date(),
            threadID: metadata.threadID,
            toolName: metadata.toolName,
            status: Self.status(for: eventType)
        )
        try append(event)
        try writeLatestState(for: event)
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard
            let flagIndex = arguments.firstIndex(of: "--floatmon-codex-hook"),
            arguments.indices.contains(flagIndex + 1)
        else {
            return false
        }

        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            try CodexHookWriter().write(eventType: arguments[flagIndex + 1], stdinData: data)
            exit(0)
        } catch {
            fputs("FloatMon hook writer failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private func append(_ event: AgentEvent) throws {
        let data = try JSONEncoder.floatMon.encode(event)
        var line = data
        line.append(UInt8(ascii: "\n"))

        let fd = open(paths.eventsJSONL.path, O_WRONLY | O_CREAT | O_APPEND, mode_t(0o600))
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            close(fd)
        }

        let bytesWritten = line.withUnsafeBytes { buffer in
            Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
        guard bytesWritten == line.count else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func writeLatestState(for event: AgentEvent) throws {
        let state = LatestState(provider: .codex, activityStatus: event.status, lastEvent: event)
        let data = try JSONEncoder.floatMon.encode(state)
        try data.write(to: paths.stateJSON, options: .atomic)
    }

    private struct Metadata {
        let threadID: String?
        let toolName: String?
    }

    private static func metadata(from data: Data) -> Metadata {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Metadata(threadID: nil, toolName: nil)
        }

        let threadID = object["thread_id"] as? String
            ?? object["threadId"] as? String
            ?? object["threadID"] as? String
        let toolName = object["tool_name"] as? String
            ?? object["toolName"] as? String
            ?? object["tool"] as? String
        return Metadata(threadID: threadID, toolName: toolName)
    }

    private static func status(for eventType: String) -> AgentEvent.Status {
        switch eventType {
        case "PreToolUse":
            return .running
        case "PermissionRequest":
            return .waiting
        case "PostToolUse", "Stop":
            return .completed
        default:
            return .idle
        }
    }
}

private extension JSONEncoder {
    static var floatMon: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
