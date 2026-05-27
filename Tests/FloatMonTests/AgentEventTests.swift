import XCTest
@testable import FloatMon

final class AgentEventTests: XCTestCase {
    func testDecodesValidEventLine() throws {
        let line = #"{\"provider\":\"codex\",\"type\":\"PreToolUse\",\"timestamp\":1779868647.25,\"threadID\":\"thread-1\",\"toolName\":\"exec_command\",\"status\":\"running\"}"#

        let event = try AgentEvent.decodeJSONLine(line)

        XCTAssertEqual(event.provider, .codex)
        XCTAssertEqual(event.type, "PreToolUse")
        XCTAssertEqual(event.threadID, "thread-1")
        XCTAssertEqual(event.toolName, "exec_command")
        XCTAssertEqual(event.status, .running)
    }

    func testReturnsNilForMalformedEventLine() {
        XCTAssertNil(AgentEvent.decodeLossyJSONLine("{not-json"))
    }
}
