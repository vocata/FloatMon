import Foundation

enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        }
    }

    var integrationName: String {
        switch self {
        case .codex:
            return "Hook"
        case .opencode:
            return "Plugin"
        }
    }

    var registerActionTitle: String {
        "Register \(integrationName)"
    }

    var detachActionTitle: String {
        "Detach \(integrationName)"
    }

    var registrationConfirmationMessage: String {
        switch self {
        case .codex:
            return "FloatMon will update ~/.codex/hooks.json and create a backup first."
        case .opencode:
            return "FloatMon will install ~/.config/opencode/plugins/floatmon-opencode-plugin.js and back up an existing file first."
        }
    }

    var detachConfirmationMessage: String {
        switch self {
        case .codex:
            return "FloatMon will remove only its Codex hooks from ~/.codex/hooks.json and create a backup first."
        case .opencode:
            return "FloatMon will remove its OpenCode plugin file and create a backup first."
        }
    }

    var iconText: String {
        switch self {
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        }
    }

    var supportsGoalDisplay: Bool {
        switch self {
        case .codex:
            return true
        case .opencode:
            return false
        }
    }
}
