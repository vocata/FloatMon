import Foundation

struct CodexSnapshotReader {
    let paths: CodexPaths

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

    init(paths: CodexPaths = CodexPaths()) {
        self.paths = paths
    }

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot {
        let events = readRecentEvents(limit: 8)
        let thread = readCurrentThread()
        let goal = thread.flatMap { readGoal(threadID: $0.id) }
        let status = events.first?.status ?? .idle
        let sqliteAvailable = FileManager.default.fileExists(atPath: paths.stateSQLite.path)

        return AgentSnapshot(
            provider: .codex,
            activityStatus: status,
            hookStatus: hookStatus,
            currentThread: thread,
            currentGoal: goal,
            recentEvents: events,
            lastUpdated: Date(),
            unavailableReason: sqliteAvailable ? nil : "Codex sqlite state is unavailable"
        )
    }

    func readRecentEvents(limit: Int) -> [AgentEvent] {
        guard
            let content = try? String(contentsOf: paths.eventsJSONL, encoding: .utf8)
        else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { AgentEvent.decodeLossyJSONLine(String($0)) }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    private func readCurrentThread() -> AgentThreadSummary? {
        guard FileManager.default.fileExists(atPath: paths.stateSQLite.path) else { return nil }
        let query = "select id, title, cwd, tokens_used as tokensUsed, updated_at_ms as updatedAtMS from threads order by updated_at_ms desc limit 1;"
        guard let row: ThreadRow = runSQLite(path: paths.stateSQLite.path, query: query)?.first else { return nil }

        return AgentThreadSummary(
            id: row.id,
            title: row.title.isEmpty ? "Untitled Codex thread" : row.title,
            cwd: row.cwd,
            tokensUsed: row.tokensUsed,
            updatedAt: Date(timeIntervalSince1970: row.updatedAtMS / 1000)
        )
    }

    private func readGoal(threadID: String) -> AgentGoalSummary? {
        guard FileManager.default.fileExists(atPath: paths.goalsSQLite.path) else { return nil }
        let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")
        let query = "select objective, status, token_budget as tokenBudget, tokens_used as tokensUsed, time_used_seconds as timeUsedSeconds from thread_goals where thread_id='\(escapedThreadID)' limit 1;"
        guard let row: GoalRow = runSQLite(path: paths.goalsSQLite.path, query: query)?.first else { return nil }

        return AgentGoalSummary(
            objective: row.objective,
            status: row.status,
            tokenBudget: row.tokenBudget,
            tokensUsed: row.tokensUsed,
            timeUsedSeconds: row.timeUsedSeconds
        )
    }

    private func runSQLite<Row: Decodable>(path: String, query: String) -> [Row]? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", path, query]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode([Row].self, from: data)
    }
}
