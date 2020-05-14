import class Foundation.Bundle
import XCTest

final class TestCommandCliTests: XCTestCase {
    func testRunningUsingLocalCommand() throws {
        mendozaTest(config: "config.json", deviceName: "iPhone 11 Pro Max", deviceRuntime: "13.2.2", retryCount: 1)
    }
}
