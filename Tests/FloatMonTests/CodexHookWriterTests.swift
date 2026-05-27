import XCTest
@testable import FloatMon

final class CodexHookWriterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testWritesEventLineAndLatestState() throws {
        let writer = CodexHookWriter(paths: CodexPaths(codexHome: root))
        let payload = #"{"thread_id":"thread-1","tool_name":"exec_command"}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: payload)

        let events = try String(contentsOf: root.appendingPathComponent("floatmon/events.jsonl"), encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"PreToolUse""#))
        XCTAssertTrue(events.contains(#""threadID":"thread-1""#))
        XCTAssertTrue(events.contains(#""toolName":"exec_command""#))

        let state = try String(contentsOf: root.appendingPathComponent("floatmon/state.json"), encoding: .utf8)
        XCTAssertTrue(state.contains(#""activityStatus":"running""#))
    }
}
