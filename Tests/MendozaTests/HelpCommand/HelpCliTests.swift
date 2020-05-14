import class Foundation.Bundle
import XCTest

final class HelpCliTests: XCTestCase {
    func testHelpCommand() throws {
        let helpText = """
        Usage:

            $ mendoza COMMAND

              Parallelize Apple\'s UI tests over multiple physical nodes

        Commands:

            + test                Dispatch UI tests
            + configuration       Configure dispatcher
            + plugin              Customize and extend the dispatcher\'s functionality
            + mendoza             Internal


        Options:

            -h, --help        Show help banner of specified command
            -v, --version     Show the version of the tool
        """

        AssertExecuteCommand(command: "mendoza --help", expected: helpText)
        AssertExecuteCommand(command: "mendoza -h", expected: helpText)
        AssertExecuteCommand(command: "mendoza", expected: helpText)
    }

    func testVersionCommand() throws {
        let versionText = "1.7.0"

        AssertExecuteCommand(command: "mendoza --version", expected: versionText)
        AssertExecuteCommand(command: "mendoza -v", expected: versionText)
    }
}
