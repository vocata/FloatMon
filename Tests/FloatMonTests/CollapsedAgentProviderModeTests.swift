import XCTest
@testable import FloatMon

final class CollapsedAgentProviderModeTests: XCTestCase {
    func testLeftSwipeMovesToNextProviderWithoutCyclingPastEnd() {
        XCTAssertEqual(CollapsedAgentProviderMode.target(current: .codex, swipeDirection: .left), .opencode)
        XCTAssertEqual(CollapsedAgentProviderMode.target(current: .opencode, swipeDirection: .left), .opencode)
    }

    func testRightSwipeMovesToPreviousProviderWithoutCyclingPastStart() {
        XCTAssertEqual(CollapsedAgentProviderMode.target(current: .opencode, swipeDirection: .right), .codex)
        XCTAssertEqual(CollapsedAgentProviderMode.target(current: .codex, swipeDirection: .right), .codex)
    }
}
