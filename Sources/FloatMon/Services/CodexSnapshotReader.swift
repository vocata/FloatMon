import Foundation

struct CodexSnapshotReader {
    let paths: CodexPaths
    private static let recentEventReadByteLimit: UInt64 = 384 * 1024

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
        let events = readRecentEvents(limit: 20)
        let thread = readCurrentThread()
        let goal = thread.flatMap { readGoal(threadID: $0.id) }
        let sqliteAvailable = FileManager.default.fileExists(atPath: paths.stateSQLite.path)

        return AgentSnapshot(
            provider: .codex,
            latestEventType: events.first?.type,
            hookStatus: hookStatus,
            currentThread: thread,
            currentGoal: goal,
            recentEvents: events,
            lastUpdated: Date(),
            unavailableReason: sqliteAvailable ? nil : "Codex sqlite state is unavailable"
        )
    }

    func readRecentEvents(limit: Int) -> [AgentEvent] {
        let events = eventLogURLs()
            .flatMap(readEvents)
            .sorted { $0.timestamp > $1.timestamp }

        var recentEvents: [AgentEvent] = []
        for event in events {
            guard recentEvents.count < limit else { break }
            if recentEvents.last.map({ Self.isDuplicate(event, of: $0) }) == true {
                continue
            }
            recentEvents.append(event)
        }
        return recentEvents
    }

    private func readEvents(from url: URL) -> [AgentEvent] {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let fileSize = try handle.seekToEnd()
            let offset = fileSize > Self.recentEventReadByteLimit
                ? fileSize - Self.recentEventReadByteLimit
                : 0
            try handle.seek(toOffset: offset)
            guard var data = try handle.readToEnd() else { return [] }

            if offset > 0 {
                guard let firstNewline = data.firstIndex(of: 0x0A) else { return [] }
                data.removeSubrange(data.startIndex...firstNewline)
            }

            guard let content = String(data: data, encoding: .utf8) else { return [] }
            return content
                .split(separator: "\n")
                .compactMap { AgentEvent.decodeLossyJSONLine(String($0)) }
        } catch {
            return []
        }
    }

    private func eventLogURLs() -> [URL] {
        guard let eventFiles = try? FileManager.default.contentsOfDirectory(
            at: paths.providerDirectory(provider: .codex),
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return eventFiles.filter { $0.pathExtension == "jsonl" }
    }

    private static func isDuplicate(_ event: AgentEvent, of previousEvent: AgentEvent) -> Bool {
        event.provider == previousEvent.provider
            && event.type == previousEvent.type
            && event.threadID == previousEvent.threadID
            && event.toolName == previousEvent.toolName
            && event.detail == previousEvent.detail
            && event.message == previousEvent.message
            && abs(event.timestamp.timeIntervalSince(previousEvent.timestamp)) <= 2
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
