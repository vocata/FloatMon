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
        let writer = CodexHookWriter(paths: testPaths)
        let payload = #"{"thread_id":"thread-1","tool_name":"exec_command","tool_input":{"command":"git status --short"}}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: payload)

        let events = try String(contentsOf: eventURL(threadID: "thread-1"), encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"PreToolUse""#))
        XCTAssertTrue(events.contains(#""threadID":"thread-1""#))
        XCTAssertTrue(events.contains(#""toolName":"exec_command""#))
        XCTAssertTrue(events.contains(#""detail":"git status --short""#))
        XCTAssertFalse(events.contains(#""status""#))

        let state = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertTrue(state.contains(#""lastEvent""#))
        XCTAssertFalse(state.contains(#""activityStatus""#))
        XCTAssertFalse(state.contains(#""status""#))
    }

    func testWritesAssistantMessageFromStopPayload() throws {
        let writer = CodexHookWriter(paths: testPaths)
        let payload = #"{"session_id":"session-1","last_assistant_message":"实现完成。没有调用工具内容。"}"#.data(using: .utf8)!

        try writer.write(eventType: "Stop", stdinData: payload)

        let events = try eventLines(threadID: "session-1").map(AgentEvent.decodeJSONLine)
        XCTAssertEqual(events[0].threadID, "session-1")
        XCTAssertEqual(events[0].message, "实现完成。没有调用工具内容。")
        XCTAssertEqual(events[0].detail, "Assistant response")
    }

    func testPostToolUsePreservesLongToolDetails() throws {
        let writer = CodexHookWriter(paths: testPaths)
        let patch = """
        *** Begin Patch
        *** Update File: Sources/FloatMon/Support/ExternalHoverTooltip.swift
        @@
        -old
        +\(String(repeating: "new-content-", count: 40))
        *** End Patch
        """
        let payload = try JSONSerialization.data(withJSONObject: [
            "thread_id": "thread-1",
            "tool_name": "apply_patch",
            "tool_input": patch,
            "tool_response": "Done applying patch"
        ])

        try writer.write(eventType: "PostToolUse", stdinData: payload)

        let events = try eventLines(threadID: "thread-1").map(AgentEvent.decodeJSONLine)
        let detail = try XCTUnwrap(events[0].detail)
        XCTAssertTrue(detail.contains("*** Begin Patch"))
        XCTAssertTrue(detail.contains("*** End Patch"))
        XCTAssertTrue(detail.contains("Done applying patch"))
        XCTAssertFalse(detail.contains("..."))
    }

    func testAppendsDecodableEventsInOrder() throws {
        let writer = CodexHookWriter(paths: testPaths)
        let firstPayload = #"{"thread_id":"thread-1","tool_name":"exec_command"}"#.data(using: .utf8)!
        let secondPayload = #"{"threadId":"thread-2","toolName":"apply_patch"}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: firstPayload)
        try writer.write(eventType: "PostToolUse", stdinData: secondPayload)

        let events = try [
            eventLines(threadID: "thread-1"),
            eventLines(threadID: "thread-2")
        ].flatMap { $0 }.map(AgentEvent.decodeJSONLine)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].type, "PreToolUse")
        XCTAssertEqual(events[0].threadID, "thread-1")
        XCTAssertEqual(events[0].toolName, "exec_command")
        XCTAssertEqual(events[1].type, "PostToolUse")
        XCTAssertEqual(events[1].threadID, "thread-2")
        XCTAssertEqual(events[1].toolName, "apply_patch")
    }

    func testMalformedMetadataPayloadStillWritesDecodableEvent() throws {
        let writer = CodexHookWriter(paths: testPaths)

        try writer.write(eventType: "PermissionRequest", stdinData: Data("not-json".utf8))

        let events = try eventLines(threadID: nil).map(AgentEvent.decodeJSONLine)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, "PermissionRequest")
        XCTAssertNil(events[0].threadID)
        XCTAssertNil(events[0].toolName)
    }

    func testCreatesOutputFilesReadableOnlyByOwner() throws {
        let writer = CodexHookWriter(paths: testPaths)
        let payload = #"{"thread_id":"thread-1","tool_name":"exec_command"}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: payload)

        XCTAssertEqual(try permissions(for: eventURL(threadID: "thread-1")), 0o600)
        XCTAssertEqual(try permissions(for: stateURL), 0o600)
    }

    func testWritesDifferentThreadsToDifferentFiles() throws {
        let writer = CodexHookWriter(paths: testPaths)
        let firstPayload = #"{"thread_id":"thread-1","tool_name":"Bash"}"#.data(using: .utf8)!
        let secondPayload = #"{"thread_id":"thread-2","tool_name":"Bash"}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: firstPayload)
        try writer.write(eventType: "PreToolUse", stdinData: secondPayload)

        XCTAssertTrue(FileManager.default.fileExists(atPath: eventURL(threadID: "thread-1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventURL(threadID: "thread-2").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentsHome.appendingPathComponent("events.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentsHome.appendingPathComponent("events", isDirectory: true).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentsHome.appendingPathComponent("threads", isDirectory: true).path))
        XCTAssertEqual(try eventLines(threadID: "thread-1").count, 1)
        XCTAssertEqual(try eventLines(threadID: "thread-2").count, 1)
    }

    private var stateURL: URL {
        testPaths.stateJSON
    }

    private var agentsHome: URL {
        root
            .appendingPathComponent(".floatmon", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
    }

    private var testPaths: CodexPaths {
        CodexPaths(codexHome: root, agentsHome: agentsHome)
    }

    private func eventURL(threadID: String?) -> URL {
        testPaths.eventLogURL(threadID: threadID)
    }

    private func eventLines(threadID: String?) throws -> [String] {
        let events = try String(contentsOf: eventURL(threadID: threadID), encoding: .utf8)
        return events.split(separator: "\n").map(String.init)
    }

    private func permissions(for url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}
