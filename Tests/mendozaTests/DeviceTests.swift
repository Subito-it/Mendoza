@testable import mendoza
import XCTest

final class DeviceTests: XCTestCase {
    func testRecentDevicesHavePointSizes() {
        XCTAssertEqual(pointSize("iPhone 16"), CGSize(width: 393, height: 852))
        XCTAssertEqual(pointSize("iPhone 17"), CGSize(width: 402, height: 874))
        XCTAssertEqual(pointSize("iPhone 17 Pro Max"), CGSize(width: 440, height: 956))
        XCTAssertEqual(pointSize("iPhone Air"), CGSize(width: 420, height: 912))
        XCTAssertEqual(pointSize("iPhone SE (3rd generation)"), CGSize(width: 375, height: 667))
        XCTAssertEqual(pointSize("iPad (A16)"), CGSize(width: 820, height: 1_180))
        XCTAssertEqual(pointSize("iPad Pro 13-inch (M5)"), CGSize(width: 1_032, height: 1_376))
        XCTAssertEqual(pointSize("iPad mini (A17 Pro)"), CGSize(width: 744, height: 1_133))
    }

    private func pointSize(_ name: String) -> CGSize {
        Device(name: name, runtime: "26.2", language: nil, locale: nil).pointSize()
    }
}
