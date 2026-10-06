@testable import mendoza
import XCTest

final class TestExecuterTests: XCTestCase {
    func testLaunchFailureInStreamedOutputIsReturnedForAnalysis() throws {
        let executer = StreamingExecuter(xcodebuildChunks: [
            "Command line invocation:\n    xcodebuild test-without-building\n",
            "Failure Reason: The request was denied by service delegate (SBMainWorkspace) for reason: Busy (\"Application failed preflight checks\").\n",
            "Testing failed:\n"
        ])
        let testExecuter = makeTestExecuter(executer: executer)

        var previewDidStartTest: Bool?
        let (output, result) = try testExecuter.launch { _, didStartTest in previewDidStartTest = didStartTest }

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(previewDidStartTest, false)
        XCTAssertFalse(testExecuter.didStartTest)
        XCTAssertTrue(OutputAnalyzer().analyze(output).isInfrastructureLaunchFailure)
    }

    func testPreviewReportsStartedTest() throws {
        let executer = StreamingExecuter(xcodebuildChunks: [
            "Test Case '-[MyAppUITests.LoginTests testLogin]' started\n",
            "Test Case '-[MyAppUITests.LoginTests testLogin]' failed (5.0 seconds)\n"
        ])
        let testExecuter = makeTestExecuter(executer: executer)

        var previewDidStartTest: Bool?
        _ = try testExecuter.launch { _, didStartTest in previewDidStartTest = didStartTest }

        XCTAssertEqual(previewDidStartTest, true)
    }

    func testOutputNotDeliveredThroughProgressIsParsed() throws {
        let executer = StreamingExecuter(
            xcodebuildChunks: ["Test Case '-[MyAppUITests.LoginTests testLogin]' started\n"],
            trailingOutput: "Test Case '-[MyAppUITests.LoginTests testLogin]' passed (1.0 seconds)\n"
        )
        let testExecuter = makeTestExecuter(executer: executer)

        let (_, result) = try testExecuter.launch { _, _ in }

        XCTAssertEqual(result.status, .passed)
        XCTAssertTrue(testExecuter.didStartTest)
    }

    private func makeTestExecuter(executer: Executer) -> TestExecuter {
        let building = Configuration.Building(
            projectPath: "/path/to/SomeProject.xcworkspace",
            buildBundleIdentifier: "com.example.app",
            testBundleIdentifier: "com.example.app.uitests",
            scheme: "MyAppUITests",
            buildConfiguration: "Debug",
            sdk: XcodeProject.SDK.ios.rawValue,
            filePatterns: FilePatterns(commaSeparatedIncludePattern: nil, commaSeparatedExcludePattern: nil),
            xcodeBuildNumber: nil
        )
        let testing = Configuration.Testing(
            maximumStdOutIdleTime: nil,
            maximumTestExecutionTime: nil,
            failingTestsRetryCount: nil,
            xcresultBlobThresholdKB: nil,
            alwaysRebootSimulators: false,
            autodeleteSlowDevices: false,
            codeCoveragePathEquivalence: nil,
            extractIndividualTestCoverage: false,
            extractTestCoveredFiles: false,
            clearDerivedDataOnCompilationFailure: false,
            skipResultMerge: false,
            disabledSimulatorServices: [],
            collectTestDiagnosticsOnFailure: false
        )

        return TestExecuter(
            executer: executer,
            testCase: TestCase(name: "testLogin", suite: "LoginTests"),
            testTarget: "MyAppUITests",
            building: building,
            testing: testing,
            node: .localhost(),
            testRunner: Simulator(id: "SIMULATOR-ID", name: "iPhone-1", device: .defaultInit()),
            runnerIndex: 0,
            verbose: false
        )
    }
}

/// Mirrors RemoteExecuter: xcodebuild output is delivered through `progress` and also returned
/// in full once the command exits.
private final class StreamingExecuter: Executer {
    var currentDirectoryPath: String?
    let homePath = "/tmp"
    let address = "localhost"
    let environment = [String: String]()
    var logger: ExecuterLogger?

    private let xcodebuildChunks: [String]
    private let trailingOutput: String

    init(xcodebuildChunks: [String], trailingOutput: String = "") {
        self.xcodebuildChunks = xcodebuildChunks
        self.trailingOutput = trailingOutput
    }

    func clone() throws -> Self {
        self
    }

    func execute(_ command: String, currentUrl: URL?, progress: ((String) -> Void)?, rethrow: (((status: Int32, output: String), Error) throws -> Void)?) throws -> String {
        try capture(command, currentUrl: currentUrl, progress: progress, rethrow: rethrow).output
    }

    func capture(_ command: String, currentUrl _: URL?, progress: ((String) -> Void)?, rethrow _: (((status: Int32, output: String), Error) throws -> Void)?) throws -> (status: Int32, output: String) {
        if command.hasPrefix("find ") {
            return (0, "/tmp/mendoza/build/Build/Products/MyAppUITests.xctestrun")
        }

        xcodebuildChunks.forEach { progress?($0) }
        let output = (xcodebuildChunks.joined() + trailingOutput).trimmingCharacters(in: .whitespacesAndNewlines)
        return (0, output)
    }

    func fileExists(atPath _: String) throws -> Bool {
        false
    }

    func download(remotePath _: String, localUrl _: URL) throws {}
    func upload(localUrl _: URL, remotePath _: String) throws {}
    func terminate() {}
}
