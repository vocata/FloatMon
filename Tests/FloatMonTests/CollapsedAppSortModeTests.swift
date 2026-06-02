import XCTest
@testable import FloatMon

final class CollapsedAppSortModeTests: XCTestCase {
    private let positiveDeltaBeyondThreshold: CGFloat = 24
    private let negativeDeltaBeyondThreshold: CGFloat = -24

    func testPositiveScrollDeltaSelectsCpuSideOfCollapsedAppSort() {
        let direction = WindowSwipeDirection.accumulatedScrollDirection(positiveDeltaBeyondThreshold)

        XCTAssertEqual(direction, .right)
        XCTAssertEqual(CollapsedAppSortMode.target(for: direction), .cpu)
    }

    func testNegativeScrollDeltaSelectsMemorySideOfCollapsedAppSort() {
        let direction = WindowSwipeDirection.accumulatedScrollDirection(negativeDeltaBeyondThreshold)

        XCTAssertEqual(direction, .left)
        XCTAssertEqual(CollapsedAppSortMode.target(for: direction), .memory)
    }
}
