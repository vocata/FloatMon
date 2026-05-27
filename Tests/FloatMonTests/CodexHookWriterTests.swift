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

    func testAppendsDecodableEventsInOrder() throws {
        let writer = CodexHookWriter(paths: CodexPaths(codexHome: root))
        let firstPayload = #"{"thread_id":"thread-1","tool_name":"exec_command"}"#.data(using: .utf8)!
        let secondPayload = #"{"threadId":"thread-2","toolName":"apply_patch"}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: firstPayload)
        try writer.write(eventType: "PostToolUse", stdinData: secondPayload)

        let events = try eventLines().map(AgentEvent.decodeJSONLine)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].type, "PreToolUse")
        XCTAssertEqual(events[0].threadID, "thread-1")
        XCTAssertEqual(events[0].toolName, "exec_command")
        XCTAssertEqual(events[0].status, .running)
        XCTAssertEqual(events[1].type, "PostToolUse")
        XCTAssertEqual(events[1].threadID, "thread-2")
        XCTAssertEqual(events[1].toolName, "apply_patch")
        XCTAssertEqual(events[1].status, .completed)
    }

    func testMalformedMetadataPayloadStillWritesDecodableEvent() throws {
        let writer = CodexHookWriter(paths: CodexPaths(codexHome: root))

        try writer.write(eventType: "PermissionRequest", stdinData: Data("not-json".utf8))

        let events = try eventLines().map(AgentEvent.decodeJSONLine)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, "PermissionRequest")
        XCTAssertNil(events[0].threadID)
        XCTAssertNil(events[0].toolName)
        XCTAssertEqual(events[0].status, .waiting)
    }

    func testCreatesEventsFileReadableOnlyByOwner() throws {
        let writer = CodexHookWriter(paths: CodexPaths(codexHome: root))
        let payload = #"{"thread_id":"thread-1","tool_name":"exec_command"}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: payload)

        let attributes = try FileManager.default.attributesOfItem(atPath: eventsURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    private var eventsURL: URL {
        root.appendingPathComponent("floatmon/events.jsonl")
    }

    private func eventLines() throws -> [String] {
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
        return events.split(separator: "\n").map(String.init)
    }
}
