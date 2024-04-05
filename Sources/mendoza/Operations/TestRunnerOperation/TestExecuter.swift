//
//  TestExecuter.swift
//  Mendoza
//
//  Created by tomas.camin on 01/06/22.
//

import Foundation

class TestExecuter {
    private let executer: Executer

    private let testCase: TestCase
    private let testTarget: String

    private let node: Node
    private let testRunner: TestRunner
    private let runnerIndex: Int

    private let building: Configuration.Building
    private let testing: Configuration.Testing
    private let xcodebuildDestination: String

    private let verbose: Bool

    private var timer: Timer?
    private var lastStdOutputUpdateTimeInterval: TimeInterval = 0

    private var testCaseStartTimeInterval: TimeInterval = 0
    private var previewCompletionBlock: ((TestCaseResult) -> Void)?

    init(executer: Executer,
         testCase: TestCase,
         testTarget: String,
         building: Configuration.Building,
         testing: Configuration.Testing,
         node: Node,
         testRunner: TestRunner,
         runnerIndex: Int,
         verbose: Bool)
    {
        self.executer = executer
        self.testCase = testCase
        self.testTarget = testTarget
        self.building = building
        self.testing = testing
        self.testRunner = testRunner
        self.node = node
        self.runnerIndex = runnerIndex
        self.verbose = verbose

        switch XcodeProject.SDK(rawValue: building.sdk)! {
        case .ios:
            xcodebuildDestination = "platform=iOS Simulator,id=\(testRunner.id)"
        case .macos:
            xcodebuildDestination = "platform=OS X,arch=x86_64"
        }
    }

    /// Execute the test case by invoking xcodebuild with test-without-building
    ///
    /// It can take a significant amount of time, up to 30s, for xcodebuild to produce the .xcresult on failure.
    /// A plausible explanation is that on failure xcodebuild need to embed (compress?) screenshots into the final result bundle.
    /// This can cause delays on the overall dispatch time particularly when failures occur near the end of the dispatch
    ///
    /// ```
    ///   SIM1   |--✅--| |---✅---| |--✅--|
    ///   SIM2      |---✅---| |--❌--|-delay-|
    ///   SIM3     |-----✅-----|     A       B
    /// ```
    ///
    /// From the console output at t = A we know that the last test of SIM2 failed and we pass that information to the previewCompletionBlock to the `previewCompletionBlock`
    /// which allows to reenconde the failing test without having to wait for the entire xcodebuild process to compleete
    ///
    /// - Parameter previewCompletionBlock: a preview of the test case result as soon as the information is extracted from the console output which can occur well before  the xcodebuild process is completed
    /// - Returns: the console output and the full test case result
    func launch(previewCompletionBlock: @escaping (TestCaseResult) -> Void) throws -> (output: String, testResult: TestCaseResult) {
        self.previewCompletionBlock = previewCompletionBlock

        var output = ""
        var testResult: TestCaseResult?

        startStdOutTimeoutHandler()
        defer { timer?.invalidate() }

        let result = try? testWithoutBuilding(executer: executer)
        output = result?.output ?? ""
        testResult = result?.testCaseResult

        if testResult == nil {
            if verbose {
                print("🚨", "No test case result for \(testCase.suite)/\(testCase.name)!".red)
            }

            let startInterval: TimeInterval = CFAbsoluteTimeGetCurrent()
            let endInterval: TimeInterval = startInterval

            testResult = TestCaseResult(node: node.address, runnerName: testRunner.name, runnerIdentifier: testRunner.id, xcResultPath: "", suite: testCase.suite, name: testCase.name, status: .failed, startInterval: startInterval, endInterval: endInterval)
            previewCompletionBlock(testResult!)
        }

        return (output: output, testResult: testResult!)
    }

    private func startStdOutTimeoutHandler() {
        if let maximumStdOutIdleTime = testing.maximumStdOutIdleTime {
            lastStdOutputUpdateTimeInterval = CFAbsoluteTimeGetCurrent()
            timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if CFAbsoluteTimeGetCurrent() - self.lastStdOutputUpdateTimeInterval > TimeInterval(maximumStdOutIdleTime) {
                    if let simulator = self.testRunner as? Simulator, let localExecuter = try? self.executer.clone() {
                        self.print("⏰", "no stdout updates for more than \(maximumStdOutIdleTime)s, stopping test", color: { $0.red })

                        // Terminating the app will make the test fail
                        let proxy = CommandLineProxy.Simulators(executer: localExecuter, verbose: self.verbose)
                        try? proxy.terminateApp(identifier: self.building.buildBundleIdentifier, on: simulator)
                        try? proxy.terminateApp(identifier: self.building.testBundleIdentifier, on: simulator)
                        if self.verbose {
                            self.print("⏰", "did terminate application", color: { $0.yellow })
                        }
                    }
                }
            }
        }
    }

    private func print(_ prefix: String, _ txt: String, color: (String) -> String = { $0.magenta }) {
        let txt = "\(prefix) \(txt) {\(runnerIndex)}"
        Swift.print(color(txt))
    }

    private func printIfVerbose(_ prefix: String, _ txt: String, color: (String) -> String = { $0.magenta }) {
        if verbose {
            print(prefix + "[\(Date().description)] Node \(node.address)", txt, color: color)
        }
    }
}

private enum XcodebuildLineEvent {
    case testStart
    case testPassed(duration: Double)
    case testFailed(duration: Double)
    case testCrashed
    case noSpaceOnDevice
    case testTimedOut

    var isTestPassed: Bool { switch self { case .testPassed: return true; default: return false } } // swiftlint:disable:this switch_case_alignment
    var isTestCrashed: Bool { switch self { case .testCrashed: return true; default: return false } } // swiftlint:disable:this switch_case_alignment
}

extension TestExecuter {
    private func findTestRun(executer: Executer) throws -> String {
        let testBundlePath = Path.testBundle.rawValue

        let testRuns = try executer.execute("find '\(testBundlePath)' -type f -name '\(building.scheme)*.xctestrun'").components(separatedBy: "\n")
        guard let testRun = testRuns.first, !testRun.isEmpty else { throw Error("No test bundle found", logger: executer.logger) }
        guard testRuns.count == 1 else { throw Error("Too many xctestrun bundles found:\n\(testRuns)", logger: executer.logger) }

        return testRun
    }

    private func testWithoutBuilding(executer: Executer) throws -> (output: String, testCaseResult: TestCaseResult?) {
        var testCaseResult: TestCaseResult?

        let testWithoutBuilding = try xcodebuildCommand(executer: executer)

        var parsedProgress = ""
        var partialProgress = ""
        let progressHandler: ((String) -> Void) = { [unowned self] progress in
            self.lastStdOutputUpdateTimeInterval = CFAbsoluteTimeGetCurrent()

            parsedProgress += progress
            partialProgress += progress
            let lines = partialProgress.components(separatedBy: "\n")
            let events = lines.compactMap(self.parseXcodebuildOutput)

            for event in events {
                switch event {
                case .testStart:
                    testCaseStartTimeInterval = CFAbsoluteTimeGetCurrent()

                    self.printIfVerbose("🛫", "\(testCase.description) started", color: { $0.yellow })
                case .testPassed:
                    let result = TestCaseResult(node: self.node.address, runnerName: self.testRunner.name, runnerIdentifier: self.testRunner.id, xcResultPath: "-", suite: self.testCase.suite, name: self.testCase.name, status: .passed, startInterval: testCaseStartTimeInterval, endInterval: CFAbsoluteTimeGetCurrent())
                    previewCompletionBlock?(result); previewCompletionBlock = nil // call preview at most once

                    testCaseResult = result
                case .testFailed, .testCrashed, .testTimedOut:
                    let result = TestCaseResult(node: self.node.address, runnerName: self.testRunner.name, runnerIdentifier: self.testRunner.id, xcResultPath: "-", suite: self.testCase.suite, name: self.testCase.name, status: .failed, startInterval: testCaseStartTimeInterval, endInterval: CFAbsoluteTimeGetCurrent())
                    previewCompletionBlock?(result); previewCompletionBlock = nil // call preview at most once

                    testCaseResult = result
                case .noSpaceOnDevice:
                    fatalError("💣 No space left on \(executer.address).")
                }
            }

            partialProgress = lines.last ?? ""
        }

        var output = try executer.execute(testWithoutBuilding, progress: progressHandler) { _, originalError in
            if !self.shouldIgnoreTestExecutionError(originalError) {
                throw originalError
            }
        }

        // It should be rare but it may happen that stdout content is not processed by the progressHandler
        output = (output.trimmingCharacters(in: .whitespacesAndNewlines)).replacingOccurrences(of: parsedProgress.trimmingCharacters(in: .whitespacesAndNewlines), with: "") + "\n"
        progressHandler(output)

        return (output: output, testCaseResult: testCaseResult)
    }

    private func xcodebuildCommand(executer: Executer) throws -> String {
        let testRun = try findTestRun(executer: executer)
        let onlyTesting = "-only-testing:'\(testTarget)/\(testCase.testIdentifier)'"
        let destinationPath = Path.logs.url.appendingPathComponent(testRunner.id).path

        var maxAllowedTestExecutionTimeParameter = ""
        if let maximumTestExecutionTime = testing.maximumTestExecutionTime {
            maxAllowedTestExecutionTimeParameter = "-maximum-test-execution-time-allowance \(maximumTestExecutionTime)"
        }

        return #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination '\#(xcodebuildDestination)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -destination-timeout 60 -test-timeouts-enabled YES \#(maxAllowedTestExecutionTimeParameter) test-without-building 2>&1 || true"#
    }

    private func parseXcodebuildOutput(line: String) -> XcodebuildLineEvent? {
        let testResultCrashMarker1 = #"Restarting after unexpected exit or crash in (.*)/(.*)\(\)"#
        let testResultCrashMarker2 = #"\s+(.*)\(\) encountered an error \(Crash:"#
        let testResultCrashMarker3 = #"Checking for crash reports corresponding to unexpected termination of"#
        let testResultCrashMarker4 = #"Restarting after unexpected exit, crash, or test timeout in (.*)\.(.*)\(\)"#
        let testResultTimeoutMarker1 = #"\s+(.*)\(\) encountered an error \(Test runner exited"# // Should be caused by the force reset of simulator
        let testResultFailureMarker1 = #"^(Testing failed:)$"#

        let testTarget = self.testTarget.replacingOccurrences(of: " ", with: "_")

        let startRegex = #"Test Case '-\[\#(testTarget)\.(.*)\]' started"#

        if line.contains(##"Code=28 "No space left on device""##) {
            return .noSpaceOnDevice
        }

        if let tests = try? line.capturedGroups(withRegexString: startRegex), tests.count == 1 {
            let testCaseName = tests[0].components(separatedBy: " ").last ?? ""
            let testCaseSuite = tests[0].components(separatedBy: " ").first ?? ""

            let startedTestCase = TestCase(name: testCaseName, suite: testCaseSuite)

            if startedTestCase.name != testCase.name || startedTestCase.suite != testCase.suite {
                fatalError("Unexpected test case found! Got \(startedTestCase) expected \(testCase)")
            }

            return .testStart
        }

        let passFailRegex = #"Test Case '-\[\#(testTarget)\.(.*)\]' (passed|failed) \((.*) seconds\)"#
        if let tests = try? line.capturedGroups(withRegexString: passFailRegex), tests.count == 3 {
            let duration = Double(tests[2]) ?? -1

            if tests[1] == "passed" {
                return .testPassed(duration: duration)
            } else if tests[1] == "failed" {
                return .testFailed(duration: duration)
            } else {
                fatalError("Unexpected test result \(tests[1]). Expecting either 'passed' or 'failed'")
            }
        }

        let timeoutRegex = #"Test Case '-\[\#(testTarget)\.(.*)\]' exceeded execution time allowance"#
        if let tests = try? line.capturedGroups(withRegexString: timeoutRegex), tests.count == 1 {
            return .testTimedOut
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker1), tests.count == 2 {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker2), tests.count == 1 {
            return .testCrashed
        }

        if line.contains(testResultCrashMarker3) {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker4), tests.count == 2 {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultTimeoutMarker1), tests.count == 1 {
            return .testFailed(duration: -1)
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultFailureMarker1), tests.count == 1 {
            return .testFailed(duration: -1)
        }

        return nil
    }

    private func shouldIgnoreTestExecutionError(_ error: Error) -> Bool {
        let ignoreErrors = ["Failed to require the PTY package", "Unable to send channel-open request"]

        for ignoreError in ignoreErrors {
            if error.errorDescription?.contains(ignoreError) == true {
                return true
            }
        }

        return false
    }
}
