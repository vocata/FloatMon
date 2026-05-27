import Foundation

struct CodexPaths {
    let codexHome: URL

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        self.codexHome = codexHome
    }

    var hooksJSON: URL {
        codexHome.appendingPathComponent("hooks.json")
    }

    var floatMonDirectory: URL {
        codexHome.appendingPathComponent("floatmon", isDirectory: true)
    }

    var eventsJSONL: URL {
        floatMonDirectory.appendingPathComponent("events.jsonl")
    }

    var stateJSON: URL {
        floatMonDirectory.appendingPathComponent("state.json")
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
}
