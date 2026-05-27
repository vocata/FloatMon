import Foundation

enum AgentMonitorMode: String, CaseIterable, Identifiable {
    case apps
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps:
            return "Apps"
        case .agent:
            return "Agent"
        }
    }
}
