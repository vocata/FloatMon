import Foundation

struct OpenCodePluginRegistrationResult: Equatable {
    let backupURL: URL?
}

struct OpenCodePluginRegistrationService {
    private static let marker = "FLOATMON_OPENCODE_PLUGIN"

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
            let plugin = try? String(contentsOf: paths.openCodePluginJS, encoding: .utf8)
        else {
            return false
        }

        return plugin.contains(Self.marker)
            && plugin.contains(Self.escapedJavaScriptString(executablePath))
            && plugin.contains("--floatmon-opencode-hook")
            && Self.supportedEventTypes.allSatisfy { plugin.contains("\"\($0)\"") }
    }

    func register(executablePath: String) throws -> OpenCodePluginRegistrationResult {
        try fileManager.createDirectory(at: paths.openCodePluginsDirectory, withIntermediateDirectories: true)
        let backupURL = try backupExistingPlugin(kind: .register)
        let plugin = Self.pluginSource(executablePath: executablePath)
        try plugin.write(to: paths.openCodePluginJS, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.openCodePluginJS.path)
        return OpenCodePluginRegistrationResult(backupURL: backupURL)
    }

    func detach() throws -> OpenCodePluginRegistrationResult {
        try fileManager.createDirectory(at: paths.openCodePluginsDirectory, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: paths.openCodePluginJS.path) else {
            return OpenCodePluginRegistrationResult(backupURL: nil)
        }

        let backupURL = try backupExistingPlugin(kind: .unregister)
        try fileManager.removeItem(at: paths.openCodePluginJS)
        return OpenCodePluginRegistrationResult(backupURL: backupURL)
    }

    private func backupExistingPlugin(kind: BackupKind) throws -> URL? {
        guard fileManager.fileExists(atPath: paths.openCodePluginJS.path) else { return nil }

        let backupURL = uniqueBackupPluginURL(kind: kind)
        try fileManager.copyItem(at: paths.openCodePluginJS, to: backupURL)
        return backupURL
    }

    private func uniqueBackupPluginURL(kind: BackupKind) -> URL {
        let backupURL: URL
        switch kind {
        case .register:
            backupURL = paths.backupOpenCodePluginURL(now: now())
        case .unregister:
            backupURL = paths.unregisterBackupOpenCodePluginURL(now: now())
        }
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

    private enum BackupKind {
        case register
        case unregister
    }

    private static func pluginSource(executablePath: String) -> String {
        let executable = escapedJavaScriptString(executablePath)
        return """
        // \(marker)
        import { spawn } from "node:child_process"

        const FLOATMON_EXECUTABLE = "\(executable)"
        const FLOATMON_EVENT_TYPES = new Set([
        \(supportedEventTypes.map { #"  "\#($0)""# }.joined(separator: ",\n"))
        ])

        function sendFloatMonEvent(eventType, payload) {
          return new Promise((resolve) => {
            const child = spawn(FLOATMON_EXECUTABLE, ["--floatmon-opencode-hook", eventType], {
              stdio: ["pipe", "ignore", "ignore"]
            })
            const timer = setTimeout(() => {
              child.kill()
              resolve()
            }, 5000)
            child.on("close", () => {
              clearTimeout(timer)
              resolve()
            })
            child.on("error", () => {
              clearTimeout(timer)
              resolve()
            })
            child.stdin.end(JSON.stringify(payload ?? {}))
          })
        }

        export const FloatMonOpenCodePlugin = async ({ directory, worktree, project }) => {
          const context = { directory, worktree, project }
          return {
            event: async ({ event }) => {
              if (!FLOATMON_EVENT_TYPES.has(event?.type)) return
              await sendFloatMonEvent(event.type, { event, context })
            }
          }
        }
        """
    }

    private static func escapedJavaScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static let supportedEventTypes = OpenCodeHookWriter.supportedEventTypes
}
