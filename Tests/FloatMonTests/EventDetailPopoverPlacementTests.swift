import XCTest
@testable import FloatMon

final class EventDetailPopoverPlacementTests: XCTestCase {
    func testPlacesPopoverNearClickWhenThereIsRoom() {
        let center = EventDetailPopoverPlacement.center(
            for: CGPoint(x: 40, y: 50),
            in: CGSize(width: 520, height: 460),
            popoverSize: CGSize(width: 380, height: 150),
            margin: 8
        )

        XCTAssertEqual(center.x, 238)
        XCTAssertEqual(center.y, 133)
    }

    func testClampsPopoverInsideTrailingAndBottomEdges() {
        let center = EventDetailPopoverPlacement.center(
            for: CGPoint(x: 500, y: 430),
            in: CGSize(width: 520, height: 460),
            popoverSize: CGSize(width: 380, height: 150),
            margin: 8
        )

        XCTAssertEqual(center.x, 322)
        XCTAssertEqual(center.y, 377)
    }

    func testClampsPopoverWhenContainerIsSmallerThanPopover() {
        let center = EventDetailPopoverPlacement.center(
            for: CGPoint(x: 10, y: 10),
            in: CGSize(width: 240, height: 120),
            popoverSize: CGSize(width: 380, height: 150),
            margin: 8
        )

        XCTAssertEqual(center.x, 198)
        XCTAssertEqual(center.y, 83)
    }
}
