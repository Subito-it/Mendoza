import class Foundation.Bundle
import XCTest

final class TestCommandCliTests: XCTestCase {
    func testRunningUsingLocalCommand() throws {
        mendozaTest(config: "mendoza.json", deviceName: "iPhone 11 Pro Max", deviceRuntime: "13.2.2", retryCount: 1)
    }

    func testFilterTests() throws {
        mendozaTest(config: "mendoza.json", deviceName: "iPhone 11 Pro Max", deviceRuntime: "13.2.2", retryCount: 1, includeTests: "help", excludeTests: nil)
    }

    func testRetryTests() throws {
        mendozaTest(config: "mendoza.json", deviceName: "iPhone 11 Pro Max", deviceRuntime: "13.2.2", testForStability: 2, retryCount: 0, includeTests: "help", excludeTests: nil)
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

    func testCustomTests() throws {
        let process = ProcessInfo.processInfo
        if let customLocation = process.environment["MENDOZA_TEST_LOCATION"], let customPluginData = process.environment["MENDOZA_PLUGIN_DATA"] {
            mendozaTest(
                config: "mendoza.json",
                deviceName: "iPhone 11 Pro Max",
                deviceRuntime: "13.2.2",
                retryCount: 1,
                includeTests: "smoketest",
                excludeTests: nil,
                pluginData: customPluginData,
                customLocation: customLocation
            )
        }
    }
}
