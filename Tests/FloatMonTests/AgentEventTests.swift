import XCTest
@testable import FloatMon

final class AgentEventTests: XCTestCase {
    func testDecodesValidEventLine() throws {
        let line = #"{\"provider\":\"codex\",\"type\":\"PreToolUse\",\"timestamp\":1779868647.25,\"threadID\":\"thread-1\",\"toolName\":\"exec_command\",\"detail\":\"git status\",\"message\":\"checking repo\"}"#

        let event = try AgentEvent.decodeJSONLine(line)

        XCTAssertEqual(event.provider, .codex)
        XCTAssertEqual(event.type, "PreToolUse")
        XCTAssertEqual(event.threadID, "thread-1")
        XCTAssertEqual(event.toolName, "exec_command")
        XCTAssertEqual(event.detail, "git status")
        XCTAssertEqual(event.message, "checking repo")
    }

    func testEncodesWithoutStatusField() throws {
        let event = AgentEvent(
            provider: .codex,
            type: "PostToolUse",
            timestamp: Date(timeIntervalSince1970: 1779868647.25),
            threadID: "thread-1",
            toolName: "Bash"
        )

        let data = try JSONEncoder.floatMonTest.encode(event)
        let output = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(output.contains(#""status""#))
    }

    func testIdentifiesRichEvents() {
        let bareEvent = AgentEvent(
            provider: .codex,
            type: "Stop",
            timestamp: Date(timeIntervalSince1970: 1779868647.25),
            threadID: "thread-1",
            toolName: nil
        )
        let detailEvent = AgentEvent(
            provider: .codex,
            type: "PostToolUse",
            timestamp: Date(timeIntervalSince1970: 1779868648.25),
            threadID: "thread-1",
            toolName: "Bash",
            detail: "git status"
        )
        let messageEvent = AgentEvent(
            provider: .codex,
            type: "Stop",
            timestamp: Date(timeIntervalSince1970: 1779868649.25),
            threadID: "thread-1",
            toolName: nil,
            message: "done"
        )

        XCTAssertFalse(bareEvent.isRich)
        XCTAssertTrue(detailEvent.isRich)
        XCTAssertTrue(messageEvent.isRich)
    }

    func testBuildsCompactSummaryForHoverDisplay() {
        let longMessage = String(repeating: "a", count: 340)
        let event = AgentEvent(
            provider: .codex,
            type: "PostToolUse",
            timestamp: Date(timeIntervalSince1970: 1779868649.25),
            threadID: "thread-1",
            toolName: "Bash",
            detail: "git diff",
            message: longMessage
        )

        XCTAssertEqual(event.displayToolLabel, "Bash")
        XCTAssertEqual(event.displayBodyText, longMessage)
        XCTAssertEqual(event.compactSummary, "PostToolUse · Bash · git diff · \(longMessage)")
    }

    func testOpenCodeSessionStatusActivitySignalsMatchStatusDetail() {
        let busy = AgentEvent(
            provider: .opencode,
            type: "session.status",
            timestamp: Date(timeIntervalSince1970: 1779868647.25),
            threadID: "session-1",
            toolName: nil,
            detail: "busy"
        )
        let completed = AgentEvent(
            provider: .opencode,
            type: "session.status",
            timestamp: Date(timeIntervalSince1970: 1779868648.25),
            threadID: "session-1",
            toolName: nil,
            detail: "idle"
        )
        let retrying = AgentEvent(
            provider: .opencode,
            type: "session.status",
            timestamp: Date(timeIntervalSince1970: 1779868649.25),
            threadID: "session-1",
            toolName: nil,
            detail: "retry"
        )

        XCTAssertEqual(busy.activitySignal, .active)
        XCTAssertEqual(completed.activitySignal, .completed)
        XCTAssertEqual(retrying.activitySignal, .retrying)
    }

    func testReturnsNilForMalformedEventLine() {
        XCTAssertNil(AgentEvent.decodeLossyJSONLine("{not-json"))
    }
}

private extension JSONEncoder {
    static var floatMonTest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
