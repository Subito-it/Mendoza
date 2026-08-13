@testable import mendoza
import XCTest

final class CoreSimulatorProxyTests: XCTestCase {
    func testParsesBooleanSettings() {
        XCTAssertEqual(CoreSimulatorProxy.Setting(rawValue: "hardware_keyboard=false")?.name, "hardware_keyboard")
        XCTAssertEqual(CoreSimulatorProxy.Setting(rawValue: "display_backlight=true")?.name, "display_backlight")
        XCTAssertEqual(CoreSimulatorProxy.Setting(rawValue: "increase_contrast=0")?.name, "increase_contrast")
        XCTAssertEqual(CoreSimulatorProxy.Setting(rawValue: "dynamic_island_suppressed=yes")?.name, "dynamic_island_suppressed")
    }

    func testParsesStringSetting() {
        XCTAssertEqual(CoreSimulatorProxy.Setting(rawValue: "status_bar_time=9:41")?.name, "status_bar_time")
    }

    /// Disabling the hardware keyboard is what makes the software keyboard appear, so a value that
    /// silently parsed as `true` would break every test that types into a text field.
    func testTruthyValuesOnlyForRecognisedSpellings() {
        for truthy in ["1", "true", "TRUE", "yes", "on"] {
            guard case let .hardwareKeyboard(enabled)? = CoreSimulatorProxy.Setting(rawValue: "hardware_keyboard=\(truthy)") else {
                return XCTFail("Failed parsing \(truthy)")
            }
            XCTAssertTrue(enabled, "Expected \(truthy) to be truthy")
        }

        for falsy in ["0", "false", "no", "off", "garbage", ""] {
            guard case let .hardwareKeyboard(enabled)? = CoreSimulatorProxy.Setting(rawValue: "hardware_keyboard=\(falsy)") else {
                return XCTFail("Failed parsing \(falsy)")
            }
            XCTAssertFalse(enabled, "Expected \(falsy) to be falsy")
        }
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(CoreSimulatorProxy.Setting(rawValue: "hardware_keyboard"))
        XCTAssertNil(CoreSimulatorProxy.Setting(rawValue: "unknown_key=true"))
        XCTAssertNil(CoreSimulatorProxy.Setting(rawValue: ""))
        XCTAssertNil(CoreSimulatorProxy.Setting(rawValue: "a=b=c"))
    }

    func testReportsMissingDeviceAsFailure() {
        let result = CoreSimulatorProxy.apply(.hardwareKeyboard(enabled: false),
                                              deviceIdentifier: "DEADBEEF-0000-0000-0000-000000000000",
                                              developerDir: "/Applications/Xcode.app/Contents/Developer")

        guard case .failure = result else {
            return XCTFail("Expected a failure for an unknown device, got \(result)")
        }
    }
}
