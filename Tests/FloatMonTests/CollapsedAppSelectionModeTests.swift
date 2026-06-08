import XCTest
@testable import FloatMon

final class CollapsedAppSelectionModeTests: XCTestCase {
    func testNegativeVerticalScrollMovesToNextApp() {
        let direction = WindowVerticalSwipeDirection.accumulatedScrollDirection(-24)

        XCTAssertEqual(direction, .up)
        XCTAssertEqual(
            CollapsedAppSelectionMode.target(currentID: 10, sortedAppIDs: [10, 20, 30], swipeDirection: direction),
            20
        )
    }

    func testPositiveVerticalScrollMovesToPreviousApp() {
        let direction = WindowVerticalSwipeDirection.accumulatedScrollDirection(24)

        XCTAssertEqual(direction, .down)
        XCTAssertEqual(
            CollapsedAppSelectionMode.target(currentID: 20, sortedAppIDs: [10, 20, 30], swipeDirection: direction),
            10
        )
    }

    func testVerticalAppSelectionDoesNotCyclePastEnds() {
        XCTAssertEqual(
            CollapsedAppSelectionMode.target(currentID: 30, sortedAppIDs: [10, 20, 30], swipeDirection: .up),
            30
        )
        XCTAssertEqual(
            CollapsedAppSelectionMode.target(currentID: 10, sortedAppIDs: [10, 20, 30], swipeDirection: .down),
            10
        )
    }

    func testMissingCurrentAppFallsBackToFirstSortedApp() {
        XCTAssertEqual(
            CollapsedAppSelectionMode.target(currentID: 99, sortedAppIDs: [10, 20, 30], swipeDirection: .up),
            20
        )
        XCTAssertEqual(
            CollapsedAppSelectionMode.target(currentID: 99, sortedAppIDs: [10, 20, 30], swipeDirection: .down),
            10
        )
    }

    func testEmptyAppListReturnsNil() {
        XCTAssertNil(CollapsedAppSelectionMode.target(currentID: nil, sortedAppIDs: [], swipeDirection: .up))
    }
}
