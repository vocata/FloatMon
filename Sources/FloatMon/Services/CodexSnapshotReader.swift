import Foundation

struct CodexSnapshotReader {
    let paths: CodexPaths
    private static let usageBucketCount = 7

    private struct ThreadRow: Decodable {
        let id: String
        let title: String
        let cwd: String
        let tokensUsed: Int
        let updatedAtMS: Double
    }

    private struct GoalRow: Decodable {
        let objective: String
        let status: String
        let tokenBudget: Int?
        let tokensUsed: Int
        let timeUsedSeconds: Int
    }

    private let usageRecorder: AgentUsageRecorder
    private let eventLogReader: AgentEventLogReader

    init(paths: CodexPaths = CodexPaths(), now: @escaping () -> Date = Date.init) {
        self.paths = paths
        self.usageRecorder = AgentUsageRecorder(paths: paths, now: now)
        self.eventLogReader = AgentEventLogReader(paths: paths, provider: .codex)
    }

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot {
        try? usageRecorder.recordCurrentThreads()
        let events = readRecentEvents(limit: 20)
        let sqliteAvailable = FileManager.default.fileExists(atPath: paths.stateSQLite.path)
        let unavailableReason: String?
        let thread: AgentThreadSummary?
        if sqliteAvailable {
            do {
                thread = try readCurrentThread()
                unavailableReason = nil
            } catch {
                thread = nil
                unavailableReason = "Codex sqlite state could not be read"
            }
        } else {
            thread = nil
            unavailableReason = "Codex sqlite state is unavailable"
        }
        let goal = thread.flatMap { try? readGoal(threadID: $0.id) }
        let usageSummary = usageRecorder.readSummary(dayCount: Self.usageBucketCount)

        return AgentSnapshot(
            provider: .codex,
            latestEventType: events.first?.type,
            hookStatus: hookStatus,
            currentThread: thread,
            currentGoal: goal,
            usageSummary: usageSummary,
            recentEvents: events,
            lastUpdated: Date(),
            unavailableReason: unavailableReason
        )
    }

    func readRecentEvents(limit: Int) -> [AgentEvent] {
        eventLogReader.readRecentEvents(limit: limit)
    }

    private func readCurrentThread() throws -> AgentThreadSummary? {
        guard FileManager.default.fileExists(atPath: paths.stateSQLite.path) else { return nil }
        let query = "select id, title, cwd, tokens_used as tokensUsed, updated_at_ms as updatedAtMS from threads order by updated_at_ms desc limit 1;"
        let rows: [ThreadRow] = try SQLiteJSONRunner.runOrThrow(
            path: paths.stateSQLite.path,
            query: query,
            errorDomain: "FloatMon.CodexSnapshotReader"
        )
        guard let row = rows.first else { return nil }

        return AgentThreadSummary(
            id: row.id,
            title: row.title.isEmpty ? "Untitled Codex thread" : row.title,
            cwd: row.cwd,
            tokensUsed: row.tokensUsed,
            updatedAt: Date(timeIntervalSince1970: row.updatedAtMS / 1000)
        )
    }

    private func readGoal(threadID: String) throws -> AgentGoalSummary? {
        guard FileManager.default.fileExists(atPath: paths.goalsSQLite.path) else { return nil }
        let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")
        let query = "select objective, status, token_budget as tokenBudget, tokens_used as tokensUsed, time_used_seconds as timeUsedSeconds from thread_goals where thread_id='\(escapedThreadID)' limit 1;"
        let rows: [GoalRow] = try SQLiteJSONRunner.runOrThrow(
            path: paths.goalsSQLite.path,
            query: query,
            errorDomain: "FloatMon.CodexSnapshotReader"
        )
        guard let row = rows.first else { return nil }

        return AgentGoalSummary(
            objective: row.objective,
            status: row.status,
            tokenBudget: row.tokenBudget,
            tokensUsed: row.tokensUsed,
            timeUsedSeconds: row.timeUsedSeconds
        )
    }

}
