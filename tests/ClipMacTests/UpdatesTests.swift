import XCTest
@testable import ClipMac

final class UpdatesTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertTrue(Updates.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(Updates.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(Updates.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(Updates.isNewer("0.1", than: "0.1.1"))
    }
}
