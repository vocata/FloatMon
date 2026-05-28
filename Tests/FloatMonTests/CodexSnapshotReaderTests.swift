import XCTest
@testable import FloatMon

final class CodexSnapshotReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: agentsHome,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testReadsRecentEventsAndIgnoresMalformedLines() throws {
        try """
        {"provider":"codex","type":"PreToolUse","timestamp":1779868647.25,"threadID":"thread-1","toolName":"exec_command","status":"running"}
        not-json
        {"provider":"codex","type":"Stop","timestamp":1779868650.25,"threadID":"thread-1","status":"completed"}
        """.write(to: eventURL(threadID: "thread-1"), atomically: true, encoding: .utf8)
        let reader = CodexSnapshotReader(paths: testPaths)

        let events = reader.readRecentEvents(limit: 5)

        XCTAssertEqual(events.map(\.type), ["Stop", "PreToolUse"])
    }

    func testRecentEventsCollapseAdjacentDuplicates() throws {
        try """
        {"provider":"codex","type":"PostToolUse","timestamp":1779868648.25,"threadID":"thread-1","toolName":"Bash","detail":"git status","status":"completed"}
        {"provider":"codex","type":"Stop","timestamp":1779868650.24,"threadID":"thread-1","message":"done","status":"completed"}
        {"provider":"codex","type":"Stop","timestamp":1779868650.25,"threadID":"thread-1","message":"done","status":"completed"}
        """.write(to: eventURL(threadID: "thread-1"), atomically: true, encoding: .utf8)
        let reader = CodexSnapshotReader(paths: testPaths)

        let events = reader.readRecentEvents(limit: 5)

        XCTAssertEqual(events.map(\.type), ["Stop", "PostToolUse"])
        XCTAssertEqual(events[0].message, "done")
        XCTAssertEqual(events[1].detail, "git status")
    }

    func testSnapshotIncludesTwentyRecentEvents() throws {
        let lines = (1...21).map { index in
            #"{"provider":"codex","type":"Stop","timestamp":\#(1779868600 + index),"threadID":"thread-\#(index)","status":"completed"}"#
        }
        try lines.joined(separator: "\n").write(to: eventURL(threadID: "thread-bulk"), atomically: true, encoding: .utf8)
        let reader = CodexSnapshotReader(paths: testPaths)

        let snapshot = reader.readSnapshot(hookStatus: .registered)

        XCTAssertEqual(snapshot.recentEvents.count, 20)
        XCTAssertEqual(snapshot.recentEvents.first?.threadID, "thread-21")
        XCTAssertEqual(snapshot.recentEvents.last?.threadID, "thread-2")
    }

    func testReadsRecentEventsFromCodexProviderDirectoryOnly() throws {
        try #"{"provider":"codex","type":"PostToolUse","timestamp":1779868650.25,"threadID":"thread-1","toolName":"Bash","detail":"done"}"#
            .write(to: eventURL(threadID: "thread-1"), atomically: true, encoding: .utf8)
        try #"{"provider":"codex","type":"Stop","timestamp":1779868652.25,"threadID":"thread-2","message":"done"}"#
            .write(to: eventURL(threadID: "thread-2"), atomically: true, encoding: .utf8)
        try #"{"provider":"codex","type":"SessionStart","timestamp":1779868654.25,"threadID":"legacy-thread"}"#
            .write(to: agentsHome.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        let oldThreadsURL = agentsHome
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent("legacy-thread", isDirectory: true)
            .appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(
            at: oldThreadsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"provider":"codex","type":"SessionStart","timestamp":1779868656.25,"threadID":"old-thread-dir"}"#
            .write(to: oldThreadsURL, atomically: true, encoding: .utf8)
        let reader = CodexSnapshotReader(paths: testPaths)

        let events = reader.readRecentEvents(limit: 5)

        XCTAssertEqual(events.map(\.type), ["Stop", "PostToolUse"])
        XCTAssertEqual(events.map(\.threadID), ["thread-2", "thread-1"])
    }

    func testRecentEventsReadTailOfLargeThreadFiles() throws {
        let newerButOldLine = #"{"provider":"codex","type":"SessionStart","timestamp":1779868700.25,"threadID":"thread-1"}"#
        let spacer = String(repeating: "not-json\n", count: 55_000)
        let recentLine = #"{"provider":"codex","type":"Stop","timestamp":1779868650.25,"threadID":"thread-1","message":"tail"}"#
        try [newerButOldLine, spacer, recentLine].joined(separator: "\n")
            .write(to: eventURL(threadID: "thread-1"), atomically: true, encoding: .utf8)
        let reader = CodexSnapshotReader(paths: testPaths)

        let events = reader.readRecentEvents(limit: 5)

        XCTAssertEqual(events.map(\.type), ["Stop"])
        XCTAssertEqual(events.first?.message, "tail")
    }

    func testMissingSqliteFilesReturnUnavailableSnapshot() {
        let reader = CodexSnapshotReader(paths: testPaths)

        let snapshot = reader.readSnapshot(hookStatus: .missing)

        XCTAssertEqual(snapshot.hookStatus, .missing)
        XCTAssertNotNil(snapshot.unavailableReason)
    }

    func testSnapshotPreservesSqliteTextFieldsContainingPipes() throws {
        let paths = testPaths
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

    private var agentsHome: URL {
        root
            .appendingPathComponent(".floatmon", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
    }

    private var testPaths: CodexPaths {
        CodexPaths(codexHome: root, agentsHome: agentsHome)
    }

    private func eventURL(threadID: String?) throws -> URL {
        let url = testPaths.eventLogURL(threadID: threadID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return url
    }
}
