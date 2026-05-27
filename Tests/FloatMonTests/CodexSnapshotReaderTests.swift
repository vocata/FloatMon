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
}
