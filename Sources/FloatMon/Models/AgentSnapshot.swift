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

struct AgentUsageBucket: Equatable {
    let date: Date
    let tokensUsed: Int
    let threadCount: Int
}

struct AgentUsageSummary: Equatable {
    let totalTokens: Int
    let threadCount: Int
    let buckets: [AgentUsageBucket]
    let lastCapturedAt: Date?

    var peakTokens: Int {
        buckets.map(\.tokensUsed).max() ?? 0
    }

    var todayTokens: Int {
        buckets.last?.tokensUsed ?? 0
    }

    var averageTokensPerDay: Int {
        guard !buckets.isEmpty else { return 0 }
        let total = buckets.reduce(0) { $0 + $1.tokensUsed }
        return Int((Double(total) / Double(buckets.count)).rounded())
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
        latestEventType: nil,
        hookStatus: .unknown,
        currentThread: nil,
        currentGoal: nil,
        usageSummary: nil,
        recentEvents: [],
        lastUpdated: nil,
        unavailableReason: nil
    )

    let provider: AgentProvider
    let latestEventType: String?
    let hookStatus: AgentHookStatus
    let currentThread: AgentThreadSummary?
    let currentGoal: AgentGoalSummary?
    let usageSummary: AgentUsageSummary?
    let recentEvents: [AgentEvent]
    let lastUpdated: Date?
    let unavailableReason: String?
}
