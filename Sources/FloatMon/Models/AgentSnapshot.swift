import Foundation

struct AgentThreadSummary: Equatable {
    let id: String
    let title: String
    let cwd: String
    let tokensUsed: Int
    let updatedAt: Date
}

struct AgentGoalSummary: Equatable {
    let objective: String
    let status: String
    let tokenBudget: Int?
    let tokensUsed: Int
    let timeUsedSeconds: Int

    var budgetProgress: Double? {
        guard let tokenBudget, tokenBudget > 0 else { return nil }
        return min(max(Double(tokensUsed) / Double(tokenBudget), 0), 1)
    }
}

enum AgentHookStatus: Equatable {
    case unknown
    case missing
    case registered
    case declined
    case failed(String)

    var label: String {
        switch self {
        case .unknown:
            return "Checking hooks"
        case .missing:
            return "Hook not registered"
        case .registered:
            return "Hook active"
        case .declined:
            return "Hook skipped"
        case .failed:
            return "Hook error"
        }
    }
}

struct AgentSnapshot: Equatable {
    static let empty = AgentSnapshot(
        provider: .codex,
        activityStatus: .idle,
        hookStatus: .unknown,
        currentThread: nil,
        currentGoal: nil,
        recentEvents: [],
        lastUpdated: nil,
        unavailableReason: nil
    )

    let provider: AgentProvider
    let activityStatus: AgentEvent.Status
    let hookStatus: AgentHookStatus
    let currentThread: AgentThreadSummary?
    let currentGoal: AgentGoalSummary?
    let recentEvents: [AgentEvent]
    let lastUpdated: Date?
    let unavailableReason: String?
}
