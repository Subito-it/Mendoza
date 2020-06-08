import class Foundation.Bundle
import XCTest

final class TestCommandCliTests: XCTestCase {
    func testRunningUsingLocalCommand() throws {
        mendozaTest(config: "mendoza.json", deviceName: "iPhone 11 Pro Max", deviceRuntime: "13.2.2", retryCount: 1)
    }

    func testFilterTests() throws {
        mendozaTest(config: "mendoza.json", deviceName: "iPhone 11 Pro Max", deviceRuntime: "13.2.2", retryCount: 1, includeTests: "help", excludeTests: nil)
    }

    func testPluginTest() throws {
//        mendoza(command: "mendoza plugin init mendoza.json precompilation --accept")
    }

    func testDebugPlugin() throws {
        mendozaTest(
            config: "mendoza.json",
            deviceName: "iPhone 11 Pro Max",
            deviceRuntime: "13.2.2",
            retryCount: 1,
            includeTests: "help",
            excludeTests: nil,
            debug: true
        )
    }
}
