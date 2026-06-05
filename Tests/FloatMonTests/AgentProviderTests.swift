import XCTest
@testable import FloatMon

final class AgentProviderTests: XCTestCase {
    func testOpenCodeProviderDisplayName() {
        XCTAssertEqual(AgentProvider.opencode.displayName, "OpenCode")
    }

    func testSupportedProvidersIncludeCodexAndOpenCode() {
        XCTAssertEqual(AgentProvider.allCases, [.codex, .opencode])
    }

    func testOnlyCodexSupportsGoalDisplay() {
        XCTAssertTrue(AgentProvider.codex.supportsGoalDisplay)
        XCTAssertFalse(AgentProvider.opencode.supportsGoalDisplay)
    }

    func testAgentProvidersResolveLocalIcons() {
        XCTAssertNotNil(AgentIconResolver.icon(for: .codex))
        XCTAssertNotNil(AgentIconResolver.icon(for: .opencode))
    }

    func testEmptyProviderSnapshotUsesSelectedProviderAndHookStatus() {
        let snapshot = AgentSnapshot.empty(provider: .opencode, hookStatus: .missing)

        XCTAssertEqual(snapshot.provider, .opencode)
        XCTAssertEqual(snapshot.hookStatus, .missing)
        XCTAssertNil(snapshot.unavailableReason)
    }

    @MainActor
    func testAgentStoreCanSelectOpenCodeProvider() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = CodexPaths(codexHome: root.appendingPathComponent(".codex", isDirectory: true))
        let store = AgentStore(paths: paths, refreshInterval: 3600, executablePath: "/tmp/FloatMon")
        defer { store.stop() }

        store.selectProvider(.opencode)

        XCTAssertEqual(store.snapshot.provider, .opencode)
        XCTAssertEqual(store.snapshot.hookStatus, .missing)
    }
}
