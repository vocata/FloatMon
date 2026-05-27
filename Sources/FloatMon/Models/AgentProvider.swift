import Foundation

enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        }
    }
}
