import XCTest
@testable import FloatMon

final class WindowDragBridgeTests: XCTestCase {
    func testHeaderClickRunsImmediately() {
        XCTAssertEqual(
            WindowClickPolicy.resolution(clickCount: 1),
            .performClickImmediately
        )
    }

    func testDoubleClickIsTreatedAsRegularClick() {
        XCTAssertEqual(
            WindowClickPolicy.resolution(clickCount: 2),
            .performClickImmediately
        )
    }
}
