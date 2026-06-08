import Foundation

struct CodexPaths {
    let codexHome: URL
    let floatMonHome: URL
    let agentsHome: URL
    let openCodeConfigHome: URL
    let openCodeDataHome: URL

    init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        floatMonHome: URL? = nil,
        agentsHome: URL? = nil,
        openCodeConfigHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true),
        openCodeDataHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
    ) {
        self.codexHome = codexHome
        self.floatMonHome = floatMonHome
            ?? agentsHome?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".floatmon", isDirectory: true)
        self.agentsHome = agentsHome ?? self.floatMonHome.appendingPathComponent("agents", isDirectory: true)
        self.openCodeConfigHome = openCodeConfigHome
        self.openCodeDataHome = openCodeDataHome
    }

    var hooksJSON: URL {
        codexHome.appendingPathComponent("hooks.json")
    }

    var floatMonDirectory: URL {
        agentsHome
    }

    var usageDirectory: URL {
        floatMonHome.appendingPathComponent("usage", isDirectory: true)
    }

    func usageSQLite(provider: AgentProvider = .codex) -> URL {
        usageDirectory.appendingPathComponent("\(provider.rawValue).sqlite")
    }

    func providerDirectory(provider: AgentProvider = .codex) -> URL {
        floatMonDirectory.appendingPathComponent(provider.rawValue, isDirectory: true)
    }

    func eventLogURL(provider: AgentProvider = .codex, threadID: String?) -> URL {
        providerDirectory(provider: provider).appendingPathComponent(Self.eventFileName(threadID: threadID))
    }

    func stateJSON(provider: AgentProvider = .codex) -> URL {
        providerDirectory(provider: provider).appendingPathComponent("state.json")
    }

    var stateJSON: URL {
        stateJSON(provider: .codex)
    }

    var stateSQLite: URL {
        codexHome.appendingPathComponent("state_5.sqlite")
    }

    var goalsSQLite: URL {
        codexHome.appendingPathComponent("goals_1.sqlite")
    }

    var openCodePluginsDirectory: URL {
        openCodeConfigHome.appendingPathComponent("plugins", isDirectory: true)
    }

    var openCodePluginJS: URL {
        openCodePluginsDirectory.appendingPathComponent("floatmon-opencode-plugin.js")
    }

    var openCodeSQLite: URL {
        openCodeDataHome.appendingPathComponent("opencode.db")
    }

    func backupHooksURL(now: Date = Date()) -> URL {
        codexHome.appendingPathComponent("hooks.floatmon-backup.\(Self.backupStamp(for: now)).json")
    }

    func unregisterBackupHooksURL(now: Date = Date()) -> URL {
        codexHome.appendingPathComponent("hooks.floatmon-unregister-backup.\(Self.backupStamp(for: now)).json")
    }

    func backupOpenCodePluginURL(now: Date = Date()) -> URL {
        openCodePluginBackupURL(kind: "backup", now: now)
    }

    func unregisterBackupOpenCodePluginURL(now: Date = Date()) -> URL {
        openCodePluginBackupURL(kind: "unregister-backup", now: now)
    }

    private func openCodePluginBackupURL(kind: String, now: Date) -> URL {
        return openCodePluginsDirectory
            .appendingPathComponent("floatmon-opencode-plugin.floatmon-\(kind).\(Self.backupStamp(for: now)).bak")
    }

    private static func backupStamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    private static func eventFileName(threadID: String?) -> String {
        let rawName = threadID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "unknown"
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = rawName.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
        let bounded = String(sanitized.prefix(120)).nilIfEmpty ?? "unknown"
        return "\(bounded).jsonl"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
