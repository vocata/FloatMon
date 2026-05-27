import Foundation

struct CodexSnapshotReader {
    let paths: CodexPaths

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
        let query = "select id,title,cwd,tokens_used,updated_at_ms from threads order by updated_at_ms desc limit 1;"
        guard let line = runSQLite(path: paths.stateSQLite.path, query: query)?.first else { return nil }
        let fields = line.components(separatedBy: "|")
        guard fields.count >= 5 else { return nil }

        return AgentThreadSummary(
            id: fields[0],
            title: fields[1].isEmpty ? "Untitled Codex thread" : fields[1],
            cwd: fields[2],
            tokensUsed: Int(fields[3]) ?? 0,
            updatedAt: Date(timeIntervalSince1970: (Double(fields[4]) ?? 0) / 1000)
        )
    }

    private func readGoal(threadID: String) -> AgentGoalSummary? {
        guard FileManager.default.fileExists(atPath: paths.goalsSQLite.path) else { return nil }
        let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")
        let query = "select objective,status,coalesce(token_budget,''),tokens_used,time_used_seconds from thread_goals where thread_id='\(escapedThreadID)' limit 1;"
        guard let line = runSQLite(path: paths.goalsSQLite.path, query: query)?.first else { return nil }
        let fields = line.components(separatedBy: "|")
        guard fields.count >= 5 else { return nil }

        return AgentGoalSummary(
            objective: fields[0],
            status: fields[1],
            tokenBudget: fields[2].isEmpty ? nil : Int(fields[2]),
            tokensUsed: Int(fields[3]) ?? 0,
            timeUsedSeconds: Int(fields[4]) ?? 0
        )
    }

    private func runSQLite(path: String, query: String) -> [String]? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
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
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(separator: "\n")
            .map(String.init)
    }
}
