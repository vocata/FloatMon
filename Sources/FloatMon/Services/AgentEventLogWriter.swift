import Darwin
import Foundation

struct AgentEventLogWriter {
    struct LatestState: Codable {
        let provider: AgentProvider
        let lastEvent: AgentEvent
    }

    let paths: CodexPaths
    private let fileManager: FileManager

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func append(_ event: AgentEvent) throws {
        let data = try JSONEncoder.floatMon.encode(event)
        var line = data
        line.append(UInt8(ascii: "\n"))

        let eventLogURL = paths.eventLogURL(provider: event.provider, threadID: event.threadID)
        try fileManager.createDirectory(
            at: eventLogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fd = open(eventLogURL.path, O_WRONLY | O_CREAT | O_APPEND, mode_t(0o600))
        guard fd >= 0 else {
            throw Self.posixError()
        }

        var locked = false
        var pendingError: Error?
        do {
            try Self.lock(fd)
            locked = true
            try Self.writeAll(line, to: fd)
        } catch {
            pendingError = error
        }

        if locked {
            do {
                try Self.unlock(fd)
            } catch {
                if pendingError == nil {
                    pendingError = error
                }
            }
        }

        if let closeError = Self.close(fd) {
            throw closeError
        }
        if let pendingError {
            throw pendingError
        }
    }

    func writeLatestState(for event: AgentEvent) throws {
        let state = LatestState(provider: event.provider, lastEvent: event)
        let data = try JSONEncoder.floatMon.encode(state)
        let stateURL = paths.stateJSON(provider: event.provider)
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: stateURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    private static func lock(_ fd: Int32) throws {
        while flock(fd, LOCK_EX) == -1 {
            guard errno == EINTR else {
                throw posixError()
            }
        }
    }

    private static func unlock(_ fd: Int32) throws {
        while flock(fd, LOCK_UN) == -1 {
            guard errno == EINTR else {
                throw posixError()
            }
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }

            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(fd, baseAddress.advanced(by: offset), buffer.count - offset)
                if result > 0 {
                    offset += result
                } else if result == -1, errno == EINTR {
                    continue
                } else {
                    throw posixError()
                }
            }
        }
    }

    private static func close(_ fd: Int32) -> POSIXError? {
        if Darwin.close(fd) == -1 {
            return posixError()
        }
        return nil
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
