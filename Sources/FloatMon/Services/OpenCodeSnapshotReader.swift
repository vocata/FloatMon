import Foundation

struct OpenCodeSnapshotReader {
    let paths: CodexPaths
    private static let usageBucketCount = 7

    private struct SessionRow: Decodable {
        let id: String
        let title: String
        let directory: String
        let timeUpdated: Int
    }

    private struct SessionUsageRow: Decodable {
        let id: String
        let timeUpdated: Int
        let tokensInput: Int
        let tokensOutput: Int
        let tokensReasoning: Int
        let tokensCacheRead: Int
        let tokensCacheWrite: Int

        var tokensUsed: Int {
            tokensInput + tokensOutput + tokensReasoning + tokensCacheRead + tokensCacheWrite
        }
    }

    private let usageRecorder: AgentUsageRecorder
    private let eventLogReader: AgentEventLogReader

    init(paths: CodexPaths = CodexPaths(), now: @escaping () -> Date = Date.init) {
        self.paths = paths
        self.usageRecorder = AgentUsageRecorder(paths: paths, provider: .opencode, now: now)
        self.eventLogReader = AgentEventLogReader(
            paths: paths,
            provider: .opencode,
            supportedEventTypes: Set(OpenCodeHookWriter.supportedEventTypes),
            duplicateWindows: ["session.status": 5]
        )
    }

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot {
        let sqliteAvailable = FileManager.default.fileExists(atPath: paths.openCodeSQLite.path)
        var unavailableReason: String?
        if !sqliteAvailable {
            unavailableReason = "OpenCode sqlite state is unavailable"
        }

        if sqliteAvailable {
            do {
                try recordCurrentSessions()
            } catch {
                unavailableReason = "OpenCode usage data could not be read"
            }
        }

        let events = readRecentEvents(limit: 20)
        let thread: AgentThreadSummary?
        if sqliteAvailable {
            do {
                thread = try readCurrentSession()
            } catch {
                thread = nil
                unavailableReason = "OpenCode sqlite state could not be read"
            }
        } else {
            thread = nil
        }
        let usageSummary = usageRecorder.readSummary(dayCount: Self.usageBucketCount)

        return AgentSnapshot(
            provider: .opencode,
            latestEventType: events.first?.type,
            hookStatus: hookStatus,
            currentThread: thread,
            currentGoal: nil,
            usageSummary: usageSummary,
            recentEvents: events,
            lastUpdated: Date(),
            unavailableReason: unavailableReason
        )
    }

    func readRecentEvents(limit: Int) -> [AgentEvent] {
        eventLogReader.readRecentEvents(limit: limit)
    }

    private func recordCurrentSessions() throws {
        guard FileManager.default.fileExists(atPath: paths.openCodeSQLite.path) else { return }
        let rows: [SessionUsageRow] = try SQLiteJSONRunner.runOrThrow(
            path: paths.openCodeSQLite.path,
            query: Self.sessionUsageQuery(ordering: ""),
            errorDomain: "FloatMon.OpenCodeSnapshotReader"
        )
        try usageRecorder.record(samples: rows.map {
            AgentThreadTokenSample(id: $0.id, tokensUsed: $0.tokensUsed, updatedAtMS: $0.timeUpdated)
        })
    }

    private func readCurrentSession() throws -> AgentThreadSummary? {
        guard FileManager.default.fileExists(atPath: paths.openCodeSQLite.path) else { return nil }
        let rows: [SessionRow] = try SQLiteJSONRunner.runOrThrow(
            path: paths.openCodeSQLite.path,
            query: Self.sessionQuery(ordering: "order by time_updated desc limit 1"),
            errorDomain: "FloatMon.OpenCodeSnapshotReader"
        )
        guard let row = rows.first else { return nil }
        let tokensUsed = (try? readSessionTokenCount(sessionID: row.id)) ?? 0

        return AgentThreadSummary(
            id: row.id,
            title: row.title.isEmpty ? "Untitled OpenCode session" : row.title,
            cwd: row.directory,
            tokensUsed: tokensUsed,
            updatedAt: Date(timeIntervalSince1970: Double(row.timeUpdated) / 1000)
        )
    }

    private func readSessionTokenCount(sessionID: String) throws -> Int {
        let escapedSessionID = sessionID.replacingOccurrences(of: "'", with: "''")
        let rows: [SessionUsageRow] = try SQLiteJSONRunner.runOrThrow(
            path: paths.openCodeSQLite.path,
            query: Self.sessionUsageQuery(ordering: "where id = '\(escapedSessionID)' limit 1"),
            errorDomain: "FloatMon.OpenCodeSnapshotReader"
        )
        return rows.first?.tokensUsed ?? 0
    }

    private static func sessionQuery(ordering: String) -> String {
        """
        select
          id,
          title,
          directory,
          time_updated as timeUpdated
        from session
        \(ordering);
        """
    }

    private static func sessionUsageQuery(ordering: String) -> String {
        """
        select
          id,
          time_updated as timeUpdated,
          tokens_input as tokensInput,
          tokens_output as tokensOutput,
          tokens_reasoning as tokensReasoning,
          tokens_cache_read as tokensCacheRead,
          tokens_cache_write as tokensCacheWrite
        from session
        \(ordering);
        """
    }

}
