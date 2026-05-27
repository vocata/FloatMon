import XCTest
@testable import FloatMon

final class CodexSnapshotReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("floatmon", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testReadsRecentEventsAndIgnoresMalformedLines() throws {
        let eventsURL = root.appendingPathComponent("floatmon/events.jsonl")
        try """
        {"provider":"codex","type":"PreToolUse","timestamp":1779868647.25,"threadID":"thread-1","toolName":"exec_command","status":"running"}
        not-json
        {"provider":"codex","type":"Stop","timestamp":1779868650.25,"threadID":"thread-1","status":"completed"}
        """.write(to: eventsURL, atomically: true, encoding: .utf8)
        let reader = CodexSnapshotReader(paths: CodexPaths(codexHome: root))

        let events = reader.readRecentEvents(limit: 5)

        XCTAssertEqual(events.map(\.type), ["Stop", "PreToolUse"])
    }

    func testMissingSqliteFilesReturnUnavailableSnapshot() {
        let reader = CodexSnapshotReader(paths: CodexPaths(codexHome: root))

        let snapshot = reader.readSnapshot(hookStatus: .missing)

        XCTAssertEqual(snapshot.hookStatus, .missing)
        XCTAssertNotNil(snapshot.unavailableReason)
    }

    func testSnapshotPreservesSqliteTextFieldsContainingPipes() throws {
        let paths = CodexPaths(codexHome: root)
        try runSQLite(
            path: paths.stateSQLite.path,
            query: """
            create table threads (
              id text,
              title text,
              cwd text,
              tokens_used integer,
              updated_at_ms integer
            );
            insert into threads values (
              'thread-1',
              'Investigate | parser',
              '/tmp/project|with|pipes',
              123,
              1779868650250
            );
            """
        )
        try runSQLite(
            path: paths.goalsSQLite.path,
            query: """
            create table thread_goals (
              thread_id text,
              objective text,
              status text,
              token_budget integer,
              tokens_used integer,
              time_used_seconds integer
            );
            insert into thread_goals values (
              'thread-1',
              'Keep | objective intact',
              'active',
              500,
              200,
              12
            );
            """
        )
        let reader = CodexSnapshotReader(paths: paths)

        let snapshot = reader.readSnapshot(hookStatus: .registered)

        XCTAssertEqual(snapshot.currentThread?.title, "Investigate | parser")
        XCTAssertEqual(snapshot.currentThread?.cwd, "/tmp/project|with|pipes")
        XCTAssertEqual(snapshot.currentThread?.tokensUsed, 123)
        XCTAssertEqual(snapshot.currentGoal?.objective, "Keep | objective intact")
        XCTAssertEqual(snapshot.currentGoal?.tokenBudget, 500)
    }

    private func runSQLite(path: String, query: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
