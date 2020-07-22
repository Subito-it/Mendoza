import class Foundation.Bundle
import XCTest

final class ConfigurationCommandCliTests: XCTestCase {
    func testConfigurationOnNonGitDirectory() throws {
        let text = "Git repo not inited or no refs found!"

        AssertExecuteCommand(command: "mendoza configuration init", expected: text, exitCode: .init(255))
    }
}
