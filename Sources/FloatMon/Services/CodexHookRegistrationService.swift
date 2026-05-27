import Foundation

struct CodexHookRegistrationResult: Equatable {
    let backupURL: URL
}

struct CodexHookRegistrationService {
    private static let events = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Stop"
    ]

    let paths: CodexPaths
    private let fileManager: FileManager
    private let now: () -> Date

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.paths = paths
        self.fileManager = fileManager
        self.now = now
    }

    func isRegistered(executablePath: String) -> Bool {
        guard
            let root = try? loadRoot(),
            let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }

        return Self.events.allSatisfy { event in
            let command = Self.command(executablePath: executablePath, event: event)
            return eventHookCommands(for: event, in: hooks)
                .contains(command)
        }
    }

    func register(executablePath: String) throws -> CodexHookRegistrationResult {
        try fileManager.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: paths.hooksJSON.path) {
            try #"{"hooks":{}}"#.write(to: paths.hooksJSON, atomically: true, encoding: .utf8)
        }

        let backupURL = uniqueBackupHooksURL()
        try fileManager.copyItem(at: paths.hooksJSON, to: backupURL)

        var root = try loadRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            mergeHook(event: event, executablePath: executablePath, into: &hooks)
        }
        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: paths.hooksJSON, options: .atomic)
        return CodexHookRegistrationResult(backupURL: backupURL)
    }

    private func loadRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: paths.hooksJSON)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? ["hooks": [String: Any]()]
    }

    private func uniqueBackupHooksURL() -> URL {
        let backupURL = paths.backupHooksURL(now: now())
        guard fileManager.fileExists(atPath: backupURL.path) else {
            return backupURL
        }

        let directoryURL = backupURL.deletingLastPathComponent()
        let baseName = backupURL.deletingPathExtension().lastPathComponent
        let pathExtension = backupURL.pathExtension
        var index = 1

        while true {
            let candidate = directoryURL
                .appendingPathComponent("\(baseName).\(index)")
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func eventHookCommands(for event: String, in hooks: [String: Any]) -> [String] {
        guard let entries = hooks[event] as? [[String: Any]] else { return [] }
        return entries.flatMap { entry -> [String] in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return [] }
            return hookList.compactMap { $0["command"] as? String }
        }
    }

    private func mergeHook(event: String, executablePath: String, into hooks: inout [String: Any]) {
        let command = Self.command(executablePath: executablePath, event: event)
        var entries = hooks[event] as? [[String: Any]] ?? []
        let alreadyRegistered = entries.contains { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
            return hookList.contains { ($0["command"] as? String) == command }
        }

        guard !alreadyRegistered else {
            hooks[event] = entries
            return
        }

        entries.append([
            "hooks": [
                [
                    "command": command,
                    "type": "command",
                    "timeout": event == "PermissionRequest" ? 86400 : 5
                ]
            ]
        ])
        hooks[event] = entries
    }

    static func command(executablePath: String, event: String) -> String {
        let escapedPath = executablePath.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escapedPath)' --floatmon-codex-hook \(event)"
    }
}
