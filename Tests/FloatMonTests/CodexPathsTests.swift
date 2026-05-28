import XCTest
@testable import FloatMon

final class CodexPathsTests: XCTestCase {
    func testAgentFilesLiveUnderAgentsHome() {
        let codexHome = URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
        let agentsHome = URL(fileURLWithPath: "/tmp/.floatmon/agents", isDirectory: true)
        let paths = CodexPaths(codexHome: codexHome, agentsHome: agentsHome)

        XCTAssertEqual(paths.hooksJSON.path, "/tmp/codex-home/hooks.json")
        XCTAssertEqual(paths.providerDirectory(provider: .codex).path, "/tmp/.floatmon/agents/codex")
        XCTAssertEqual(paths.eventLogURL(threadID: "thread-1").path, "/tmp/.floatmon/agents/codex/thread-1.jsonl")
        XCTAssertEqual(paths.eventLogURL(threadID: "thread/with spaces").path, "/tmp/.floatmon/agents/codex/thread_with_spaces.jsonl")
        XCTAssertEqual(paths.eventLogURL(threadID: nil).path, "/tmp/.floatmon/agents/codex/unknown.jsonl")
        XCTAssertEqual(paths.stateJSON.path, "/tmp/.floatmon/agents/codex/state.json")
        XCTAssertEqual(paths.stateSQLite.path, "/tmp/codex-home/state_5.sqlite")
        XCTAssertEqual(paths.goalsSQLite.path, "/tmp/codex-home/goals_1.sqlite")
    }
}
