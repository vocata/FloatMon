import XCTest
@testable import FloatMon

final class OpenCodeHookWriterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonOpenCodeWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testWritesNativeEventNameToOpenCodeProviderDirectory() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let payload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "session.status",
                "properties": [
                    "sessionID": "session-1",
                    "status": [
                        "type": "idle"
                    ]
                ]
            ]
        ])

        try writer.write(eventType: "session.status", stdinData: payload)

        let events = try eventLines(sessionID: "session-1").map(AgentEvent.decodeJSONLine)
        XCTAssertEqual(events[0].provider, .opencode)
        XCTAssertEqual(events[0].type, "session.status")
        XCTAssertEqual(events[0].threadID, "session-1")
        XCTAssertEqual(events[0].detail, "idle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: testPaths.stateJSON(provider: .opencode).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testPaths.stateJSON(provider: .codex).path))
    }

    func testBusyStatusWritesRawStatusType() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let payload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "session.status",
                "properties": [
                    "sessionID": "session-1",
                    "status": [
                        "type": "busy"
                    ]
                ]
            ]
        ])

        try writer.write(eventType: "session.status", stdinData: payload)

        let event = try XCTUnwrap(eventLines(sessionID: "session-1").map(AgentEvent.decodeJSONLine).first)
        XCTAssertEqual(event.detail, "busy")
        XCTAssertNil(event.message)
    }

    func testWritesToolAndPermissionEventsWithOriginalEventNames() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let toolPayload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "tool.execute.before",
                "properties": [
                    "sessionID": "session-1",
                    "tool": "bash",
                    "args": [
                        "command": "git status --short"
                    ]
                ]
            ]
        ])
        let permissionPayload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "permission.asked",
                "properties": [
                    "sessionID": "session-1",
                    "tool": "bash",
                    "description": "run swift test"
                ]
            ]
        ])

        try writer.write(eventType: "tool.execute.before", stdinData: toolPayload)
        try writer.write(eventType: "permission.asked", stdinData: permissionPayload)

        let events = try eventLines(sessionID: "session-1").map(AgentEvent.decodeJSONLine)
        XCTAssertEqual(events.map(\.type), ["tool.execute.before", "permission.asked"])
        XCTAssertEqual(events[0].toolName, "bash")
        XCTAssertEqual(events[0].detail, "git status --short")
        XCTAssertEqual(events[1].toolName, "bash")
        XCTAssertEqual(events[1].detail, "run swift test")
    }

    func testIgnoresSessionIdleWithoutWritingFiles() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let payload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "session.idle",
                "properties": [
                    "sessionID": "session-1"
                ]
            ]
        ])

        try writer.write(eventType: "session.idle", stdinData: payload)

        XCTAssertFalse(FileManager.default.fileExists(atPath: testPaths.eventLogURL(provider: .opencode, threadID: "session-1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testPaths.stateJSON(provider: .opencode).path))
    }

    func testIgnoresUnsupportedEventsWithoutWritingFiles() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let payload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "message.updated",
                "properties": [
                    "sessionID": "session-1",
                    "message": "ignored"
                ]
            ]
        ])

        try writer.write(eventType: "message.updated", stdinData: payload)

        XCTAssertFalse(FileManager.default.fileExists(atPath: testPaths.eventLogURL(provider: .opencode, threadID: "session-1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testPaths.stateJSON(provider: .opencode).path))
    }

    func testStatusPayloadPrefersPropertiesSessionIDOverEventID() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let payload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "id": "evt-wrong",
                "type": "session.status",
                "properties": [
                    "sessionID": "session-1",
                    "status": [
                        "type": "busy"
                    ]
                ]
            ]
        ])

        try writer.write(eventType: "session.status", stdinData: payload)

        let event = try XCTUnwrap(eventLines(sessionID: "session-1").map(AgentEvent.decodeJSONLine).first)
        XCTAssertEqual(event.threadID, "session-1")
        XCTAssertEqual(event.detail, "busy")
        XCTAssertFalse(FileManager.default.fileExists(atPath: testPaths.eventLogURL(provider: .opencode, threadID: "evt-wrong").path))
    }

    func testIdleStatusWritesRawStatusType() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let payload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "session.status",
                "properties": [
                    "sessionID": "session-1",
                    "status": [
                        "type": "idle"
                    ]
                ]
            ]
        ])

        try writer.write(eventType: "session.status", stdinData: payload)

        let event = try XCTUnwrap(eventLines(sessionID: "session-1").map(AgentEvent.decodeJSONLine).first)
        XCTAssertEqual(event.detail, "idle")
        XCTAssertNil(event.message)
    }

    func testRetryStatusWritesRawStatusTypeAndMessage() throws {
        let writer = OpenCodeHookWriter(paths: testPaths)
        let payload = try JSONSerialization.data(withJSONObject: [
            "event": [
                "type": "session.status",
                "properties": [
                    "sessionID": "session-1",
                    "status": [
                        "type": "retry",
                        "attempt": 2,
                        "message": "rate limit",
                        "next": 1780567000000
                    ]
                ]
            ]
        ])

        try writer.write(eventType: "session.status", stdinData: payload)

        let event = try XCTUnwrap(eventLines(sessionID: "session-1").map(AgentEvent.decodeJSONLine).first)
        XCTAssertEqual(event.detail, "retry")
        XCTAssertEqual(event.message, "rate limit")
    }

    private var testPaths: CodexPaths {
        CodexPaths(
            codexHome: root.appendingPathComponent(".codex", isDirectory: true),
            floatMonHome: root.appendingPathComponent(".floatmon", isDirectory: true),
            openCodeConfigHome: root.appendingPathComponent(".config/opencode", isDirectory: true),
            openCodeDataHome: root.appendingPathComponent(".local/share/opencode", isDirectory: true)
        )
    }

    private func eventLines(sessionID: String?) throws -> [String] {
        let url = testPaths.eventLogURL(provider: .opencode, threadID: sessionID)
        let events = try String(contentsOf: url, encoding: .utf8)
        return events.split(separator: "\n").map(String.init)
    }
}
