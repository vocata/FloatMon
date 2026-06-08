import XCTest
@testable import FloatMon

final class OpenCodeSnapshotReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonOpenCodeSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testReadsLatestSessionAndUsageFromOpenCodeDatabase() throws {
        try createOpenCodeDatabase()
        let reader = OpenCodeSnapshotReader(paths: testPaths)

        let snapshot = reader.readSnapshot(hookStatus: .registered)

        XCTAssertEqual(snapshot.provider, .opencode)
        XCTAssertEqual(snapshot.currentThread?.id, "session-new")
        XCTAssertEqual(snapshot.currentThread?.title, "Latest session")
        XCTAssertEqual(snapshot.currentThread?.cwd, "/tmp/project")
        XCTAssertEqual(snapshot.currentThread?.tokensUsed, 45)
        XCTAssertNil(snapshot.currentGoal)
        XCTAssertNotNil(snapshot.usageSummary)
    }

    func testReadsOpenCodeSessionWhenUsageColumnsAreUnavailable() throws {
        try createOpenCodeDatabaseWithoutUsageColumns()
        let reader = OpenCodeSnapshotReader(paths: testPaths)

        let snapshot = reader.readSnapshot(hookStatus: .registered)

        XCTAssertEqual(snapshot.currentThread?.id, "session-new")
        XCTAssertEqual(snapshot.currentThread?.title, "Latest session")
        XCTAssertEqual(snapshot.currentThread?.cwd, "/tmp/project")
        XCTAssertEqual(snapshot.currentThread?.tokensUsed, 0)
        XCTAssertNil(snapshot.usageSummary)
        XCTAssertEqual(snapshot.unavailableReason, "OpenCode usage data could not be read")
    }

    func testReadsOnlyCodexEquivalentOpenCodeEventsFromExistingEventLogs() throws {
        try FileManager.default.createDirectory(at: testPaths.providerDirectory(provider: .opencode), withIntermediateDirectories: true)
        let log = """
        {"provider":"opencode","type":"message.updated","timestamp":1779868647.25,"threadID":"session-1","detail":"ignored"}
        {"provider":"opencode","type":"tool.execute.before","timestamp":1779868648.25,"threadID":"session-1","toolName":"bash","detail":"git status"}
        {"provider":"opencode","type":"session.status","timestamp":1779868649.25,"threadID":"session-1","detail":"idle","message":"done"}
        {"provider":"opencode","type":"session.idle","timestamp":1779868650.25,"threadID":"session-1","detail":"ignored"}
        {"provider":"opencode","type":"session.diff","timestamp":1779868649.25,"threadID":"session-1","detail":"ignored"}
        """
        try log.write(to: testPaths.eventLogURL(provider: .opencode, threadID: "session-1"), atomically: true, encoding: .utf8)
        let reader = OpenCodeSnapshotReader(paths: testPaths)

        let events = reader.readRecentEvents(limit: 10)

        XCTAssertEqual(events.map(\.type), ["session.status", "tool.execute.before"])
    }

    func testCollapsesRepeatedOpenCodeStatusEvents() throws {
        try FileManager.default.createDirectory(at: testPaths.providerDirectory(provider: .opencode), withIntermediateDirectories: true)
        let log = """
        {"provider":"opencode","type":"session.status","timestamp":1779868647.25,"threadID":"session-1","detail":"busy"}
        {"provider":"opencode","type":"session.status","timestamp":1779868650.25,"threadID":"session-1","detail":"busy"}
        {"provider":"opencode","type":"session.status","timestamp":1779868651.25,"threadID":"session-1","detail":"idle","message":"Bye."}
        """
        try log.write(to: testPaths.eventLogURL(provider: .opencode, threadID: "session-1"), atomically: true, encoding: .utf8)
        let reader = OpenCodeSnapshotReader(paths: testPaths)

        let events = reader.readRecentEvents(limit: 10)

        XCTAssertEqual(events.map(\.detail), ["idle", "busy"])
    }

    private var testPaths: CodexPaths {
        CodexPaths(
            codexHome: root.appendingPathComponent(".codex", isDirectory: true),
            floatMonHome: root.appendingPathComponent(".floatmon", isDirectory: true),
            openCodeConfigHome: root.appendingPathComponent(".config/opencode", isDirectory: true),
            openCodeDataHome: root.appendingPathComponent(".local/share/opencode", isDirectory: true)
        )
    }

    private func createOpenCodeDatabase() throws {
        try FileManager.default.createDirectory(at: testPaths.openCodeDataHome, withIntermediateDirectories: true)
        try runSQLite("""
        create table session (
          id text primary key,
          title text not null,
          directory text not null,
          time_updated integer not null,
          tokens_input integer default 0 not null,
          tokens_output integer default 0 not null,
          tokens_reasoning integer default 0 not null,
          tokens_cache_read integer default 0 not null,
          tokens_cache_write integer default 0 not null
        );
        insert into session values ('session-old', 'Old session', '/tmp/old', 1000, 1, 2, 3, 4, 5);
        insert into session values ('session-new', 'Latest session', '/tmp/project', 2000, 10, 11, 12, 6, 6);
        """)
    }

    private func createOpenCodeDatabaseWithoutUsageColumns() throws {
        try FileManager.default.createDirectory(at: testPaths.openCodeDataHome, withIntermediateDirectories: true)
        try runSQLite("""
        create table session (
          id text primary key,
          title text not null,
          directory text not null,
          time_updated integer not null
        );
        insert into session values ('session-new', 'Latest session', '/tmp/project', 2000);
        """)
    }

    private func runSQLite(_ query: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [testPaths.openCodeSQLite.path, query]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
