import Foundation

struct CodexPaths {
    let codexHome: URL
    let floatMonHome: URL
    let agentsHome: URL

    init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        floatMonHome: URL? = nil,
        agentsHome: URL? = nil
    ) {
        self.codexHome = codexHome
        self.floatMonHome = floatMonHome
            ?? agentsHome?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".floatmon", isDirectory: true)
        self.agentsHome = agentsHome ?? self.floatMonHome.appendingPathComponent("agents", isDirectory: true)
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

    func backupHooksURL(now: Date = Date()) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        return codexHome.appendingPathComponent("hooks.floatmon-backup.\(stamp).json")
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
