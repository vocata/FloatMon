import Foundation

struct CodexThreadTokenSample: Equatable {
    let id: String
    let tokensUsed: Int
    let updatedAtMS: Int
}

struct CodexUsageRecorder {
    let paths: CodexPaths
    private let fileManager: FileManager
    private let now: () -> Date

    private struct ThreadRow: Decodable {
        let id: String
        let tokensUsed: Int
        let updatedAtMS: Double
    }

    private struct TotalsRow: Decodable {
        let totalTokens: Int
        let threadCount: Int
        let lastCapturedAtMS: Int?
    }

    private struct BucketRow: Decodable {
        let day: String
        let tokensUsed: Int
        let threadCount: Int
    }

    init(
        paths: CodexPaths = CodexPaths(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.now = now
    }

    func recordCurrentThreads() throws {
        guard fileManager.fileExists(atPath: paths.stateSQLite.path) else { return }
        let query = "select id, tokens_used as tokensUsed, updated_at_ms as updatedAtMS from threads;"
        let rows: [ThreadRow] = runSQLite(path: paths.stateSQLite.path, query: query) ?? []
        try record(samples: rows.map {
            CodexThreadTokenSample(
                id: $0.id,
                tokensUsed: $0.tokensUsed,
                updatedAtMS: Int($0.updatedAtMS)
            )
        })
    }

    func record(samples: [CodexThreadTokenSample]) throws {
        try prepareStore()
        let day = Self.dayString(for: now())
        let seenAtMS = Int(now().timeIntervalSince1970 * 1000)
        var statements = [Self.schemaSQL, "begin immediate transaction;"]

        for sample in samples where !sample.id.isEmpty {
            let threadID = Self.sqlString(sample.id)
            let tokensUsed = max(sample.tokensUsed, 0)
            let updatedAtMS = sample.updatedAtMS
            let deltaExpression = "max(0, \(tokensUsed) - coalesce((select tokens_used from thread_token_state where thread_id = \(threadID)), \(tokensUsed)))"
            statements.append("""
            insert into daily_thread_usage (day, thread_id, tokens_used, last_captured_at_ms)
            select \(Self.sqlString(day)), \(threadID), \(deltaExpression), \(seenAtMS)
            where \(deltaExpression) > 0
            on conflict(day, thread_id) do update set
              tokens_used = tokens_used + excluded.tokens_used,
              last_captured_at_ms = excluded.last_captured_at_ms;
            """)
            statements.append("""
            insert into thread_token_state (thread_id, tokens_used, updated_at_ms, last_seen_at_ms)
            values (\(threadID), \(tokensUsed), \(updatedAtMS), \(seenAtMS))
            on conflict(thread_id) do update set
              tokens_used = excluded.tokens_used,
              updated_at_ms = excluded.updated_at_ms,
              last_seen_at_ms = excluded.last_seen_at_ms;
            """)
        }

        statements.append("commit;")
        try runSQLiteOrThrow(path: paths.usageSQLite().path, query: statements.joined(separator: "\n"))
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.usageSQLite().path)
    }

    func readSummary(dayCount: Int) -> AgentUsageSummary? {
        guard dayCount > 0, fileManager.fileExists(atPath: paths.usageSQLite().path) else { return nil }
        guard let totals: TotalsRow = runSQLite(path: paths.usageSQLite().path, query: """
        select
          coalesce((select sum(tokens_used) from daily_thread_usage), 0) as totalTokens,
          (select count(*) from thread_token_state) as threadCount,
          (select max(last_captured_at_ms) from daily_thread_usage) as lastCapturedAtMS;
        """)?.first else {
            return nil
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        guard let firstDay = calendar.date(byAdding: .day, value: 1 - dayCount, to: today) else { return nil }
        let firstDayString = Self.dayString(for: firstDay)
        let rows: [BucketRow] = runSQLite(path: paths.usageSQLite().path, query: """
        select day, coalesce(sum(tokens_used), 0) as tokensUsed, count(thread_id) as threadCount
        from daily_thread_usage
        where day >= \(Self.sqlString(firstDayString))
        group by day
        order by day asc;
        """) ?? []
        let rowsByDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
        let buckets = (0..<dayCount).compactMap { offset -> AgentUsageBucket? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            let day = Self.dayString(for: date)
            let row = rowsByDay[day]
            return AgentUsageBucket(
                date: date,
                tokensUsed: row?.tokensUsed ?? 0,
                threadCount: row?.threadCount ?? 0
            )
        }

        return AgentUsageSummary(
            totalTokens: totals.totalTokens,
            threadCount: totals.threadCount,
            buckets: buckets,
            lastCapturedAt: totals.lastCapturedAtMS.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        )
    }

    private func prepareStore() throws {
        try fileManager.createDirectory(at: paths.usageDirectory, withIntermediateDirectories: true)
        runSQLiteIgnoringFailure(
            path: paths.usageSQLite().path,
            query: "alter table daily_thread_usage add column last_captured_at_ms integer;"
        )
    }

    private static let schemaSQL = """
    create table if not exists thread_token_state (
      thread_id text primary key,
      tokens_used integer not null,
      updated_at_ms integer not null,
      last_seen_at_ms integer not null
    );
    create table if not exists daily_thread_usage (
      day text not null,
      thread_id text not null,
      tokens_used integer not null,
      last_captured_at_ms integer,
      primary key (day, thread_id)
    );
    """

    private static func sqlString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

    private func runSQLiteOrThrow(path: String, query: String) throws {
        let process = Process()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sqlite failed"
            throw NSError(domain: "FloatMon.CodexUsageRecorder", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    private func runSQLiteIgnoringFailure(path: String, query: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}
