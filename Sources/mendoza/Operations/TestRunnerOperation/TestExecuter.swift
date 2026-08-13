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
    private let outputParser: XcodebuildOutputParser

    private let verbose: Bool

    private var timerSource: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.mendoza.stdoutTimeout")
    private let syncQueue = DispatchQueue(label: "com.mendoza.stdoutTimeout.sync")
    private var _lastStdOutputUpdateTimeInterval: TimeInterval = 0
    private var lastStdOutputUpdateTimeInterval: TimeInterval {
        get { syncQueue.sync { _lastStdOutputUpdateTimeInterval } }
        set { syncQueue.sync { _lastStdOutputUpdateTimeInterval = newValue } }
    }

    private var _stdOutIdleTimes: [TimeInterval] = []
    private var stdOutIdleTimes: [TimeInterval] {
        get { syncQueue.sync { _stdOutIdleTimes } }
        set { syncQueue.sync { _stdOutIdleTimes = newValue } }
    }

    private var _didTriggerTimeout = false
    private var didTriggerTimeout: Bool {
        get { syncQueue.sync { _didTriggerTimeout } }
        set { syncQueue.sync { _didTriggerTimeout = newValue } }
    }

    private var testCaseStartTimeInterval: TimeInterval = 0
    private var previewCompletionBlock: ((TestCaseResult) -> Void)?

    /// True once the test method actually started executing (a `Test Case ... started` line was
    /// parsed). Distinguishes a genuine test failure from a simulator-level launch failure where
    /// the test never ran. Only valid to read after `launch(...)` returns.
    var didStartTest: Bool {
        testCaseStartTimeInterval > 0
    }

    init(executer: Executer,
         testCase: TestCase,
         testTarget: String,
         building: Configuration.Building,
         testing: Configuration.Testing,
         node: Node,
         testRunner: TestRunner,
         runnerIndex: Int,
         verbose: Bool) {
        self.executer = executer
        self.testCase = testCase
        self.testTarget = testTarget
        self.building = building
        self.testing = testing
        self.testRunner = testRunner
        self.node = node
        self.runnerIndex = runnerIndex
        self.verbose = verbose
        self.outputParser = XcodebuildOutputParser(testTarget: testTarget)

        switch XcodeProject.SDK(rawValue: building.sdk)! {
        case .ios:
            self.xcodebuildDestination = "platform=iOS Simulator,id=\(testRunner.id)"
        case .macos:
            self.xcodebuildDestination = "platform=OS X,arch=x86_64"
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

        defer { stopStdOutTimeoutHandler() }

        let result = try? testWithoutBuilding(executer: executer)
        output = result?.output ?? ""
        testResult = result?.testCaseResult

        // Logged only now that xcodebuild has returned: ExecuterLogger expects strictly alternating
        // start/end events, so appending an exception while the command is still in flight would
        // break the pairing when the log is written out.
        if didTriggerTimeout {
            executer.logger?.log(exception: "no stdout updates for more than \(testing.maximumStdOutIdleTime ?? 0)s, terminated app on \(testRunner.name)")
        }

        if testResult == nil {
            if verbose {
                print("🚨", "No test case result for \(testCase.suite)/\(testCase.name)!".red)
            }

            let startInterval: TimeInterval = CFAbsoluteTimeGetCurrent()
            let endInterval: TimeInterval = startInterval

            testResult = TestCaseResult(node: node.address, runnerName: testRunner.name, runnerIdentifier: testRunner.id, xcResultPath: "", suite: testCase.suite, name: testCase.name, status: .failed, startInterval: startInterval, endInterval: endInterval, averageStdOutIdleTime: nil, maxStdOutIdleTime: nil)
            previewCompletionBlock(testResult!)
        }

        return (output: output, testResult: testResult!)
    }

    private func startStdOutTimeoutHandler() {
        guard let maximumStdOutIdleTime = testing.maximumStdOutIdleTime else { return }

        lastStdOutputUpdateTimeInterval = CFAbsoluteTimeGetCurrent()

        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now() + 1, repeating: 1.0)
        source.setEventHandler { [weak self] in
            guard let self = self, !self.didTriggerTimeout else { return }

            let idleTime = CFAbsoluteTimeGetCurrent() - self.lastStdOutputUpdateTimeInterval
            if idleTime > TimeInterval(maximumStdOutIdleTime) {
                // Mark as triggered to prevent multiple firings
                self.didTriggerTimeout = true
                source.cancel()

                guard let simulator = self.testRunner as? Simulator,
                      let localExecuter = try? self.executer.clone() else { return }

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
        source.resume()
        timerSource = source
    }

    /// Disarm the stdout watchdog. Must be called as soon as the test verdict is known: after that
    /// point xcodebuild is in its post-test phase (finalizing the xcresult, collecting simulator
    /// diagnostics) where stdout is legitimately silent for far longer than `maximumStdOutIdleTime`.
    /// Terminating the test runner host during that phase breaks xcodebuild's diagnostics collection,
    /// which then blocks for its own 600s timeout while holding the runner slot.
    private func stopStdOutTimeoutHandler() {
        timerSource?.cancel()
        timerSource = nil
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
        let progressHandler: ((String) -> Void) = { [weak self] progress in
            guard let self else { return }

            // Only collect idle times after test has started
            if testCaseStartTimeInterval > 0 {
                let currentTime = CFAbsoluteTimeGetCurrent()
                let lastUpdate = self.lastStdOutputUpdateTimeInterval
                if lastUpdate > 0 {
                    let idleTime = currentTime - lastUpdate
                    self.stdOutIdleTimes.append(idleTime)
                }
                self.lastStdOutputUpdateTimeInterval = currentTime
            }

            parsedProgress += progress
            partialProgress += progress
            let lines = partialProgress.components(separatedBy: "\n")
            let events = lines.compactMap(self.outputParser.event)

            for event in events {
                switch event {
                case let .testStart(startedTestCase):
                    if startedTestCase.name != testCase.name || startedTestCase.suite != testCase.suite {
                        fatalError("Unexpected test case found! Got \(startedTestCase) expected \(testCase)")
                    }

                    testCaseStartTimeInterval = CFAbsoluteTimeGetCurrent()
                    self.startStdOutTimeoutHandler()

                    self.printIfVerbose("🛫", "\(testCase.description) started", color: { $0.yellow })
                case .testPassed:
                    self.stopStdOutTimeoutHandler()

                    let idleTimes = self.stdOutIdleTimes
                    let avgIdleTime = idleTimes.isEmpty ? nil : idleTimes.reduce(0, +) / Double(idleTimes.count)
                    let maxIdleTime = idleTimes.max()
                    let result = TestCaseResult(node: self.node.address, runnerName: self.testRunner.name, runnerIdentifier: self.testRunner.id, xcResultPath: "-", suite: self.testCase.suite, name: self.testCase.name, status: .passed, startInterval: testCaseStartTimeInterval, endInterval: CFAbsoluteTimeGetCurrent(), averageStdOutIdleTime: avgIdleTime, maxStdOutIdleTime: maxIdleTime)
                    previewCompletionBlock?(result); previewCompletionBlock = nil // call preview at most once

                    testCaseResult = result
                case .testFailed, .testCrashed, .testTimedOut:
                    self.stopStdOutTimeoutHandler()

                    let idleTimes = self.stdOutIdleTimes
                    let avgIdleTime = idleTimes.isEmpty ? nil : idleTimes.reduce(0, +) / Double(idleTimes.count)
                    let maxIdleTime = idleTimes.max()
                    let result = TestCaseResult(node: self.node.address, runnerName: self.testRunner.name, runnerIdentifier: self.testRunner.id, xcResultPath: "-", suite: self.testCase.suite, name: self.testCase.name, status: .failed, startInterval: testCaseStartTimeInterval, endInterval: CFAbsoluteTimeGetCurrent(), averageStdOutIdleTime: avgIdleTime, maxStdOutIdleTime: maxIdleTime)
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

        // Diagnostics collection is opt-in because it is very expensive: xcodebuild shells out to
        // `simctl diagnose --timeout=600`, which spends minutes gathering a ~280MB sysdiagnose into
        // the .xcresult *after* the verdict has already been parsed from stdout. The runner slot stays
        // held for the whole collection, so a single failure can take a simulator out of rotation for
        // up to 10 minutes. Passing the flag explicitly also overrides whatever the test plan sets.
        let collectDiagnosticsParameter = "-collect-test-diagnostics \(testing.collectTestDiagnosticsOnFailure ? "on-failure" : "never")"

        return #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination '\#(xcodebuildDestination)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -destination-timeout 60 -test-timeouts-enabled YES \#(collectDiagnosticsParameter) \#(maxAllowedTestExecutionTimeParameter) test-without-building 2>&1 || true"#
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
