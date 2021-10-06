//
//  TestRunnerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestRunnerOperation: BaseOperation<[TestCaseResult]> {
    // An array of TestCases sorted from the longest to the shortest estimated execution time
    var sortedTestCases: [TestCase]?
    var currentResult: [TestCaseResult]?
    var currentRunningTest = [Int: (test: TestCase, start: TimeInterval)]()
    var testRunners: [(testRunner: TestRunner, node: Node)]?

    private var testCasesCount = 0
    private var testCasesCompletedCount = 0

    private let configuration: Configuration
    private let testTarget: String
    private let productNames: [String]
    private let sdk: XcodeProject.SDK
    private let failingTestsRetryCount: Int
    private let testTimeoutSeconds: Int
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private let verbose: Bool
    private var retryCountMap = NSCountedSet()
    private var retryCount: Int { // access only from syncQueue
        retryCountMap.reduce(0) { $0 + retryCountMap.count(for: $1) }
    }
    private let xcresultBlobThresholdKB: Int?

    private enum XcodebuildLineEvent {
        case testStart(testCase: TestCase)
        case testPassed(duration: Double)
        case testFailed(duration: Double)
        case testCrashed
        case noSpaceOnDevice
        case testTimedOut

        var isTestPassed: Bool { switch self { case .testPassed: return true; default: return false } } // swiftlint:disable:this switch_case_alignment
        var isTestCrashed: Bool { switch self { case .testCrashed: return true; default: return false } } // swiftlint:disable:this switch_case_alignment
    }

    private lazy var pool: ConnectionPool<TestRunner> = {
        guard let sortedTestCases = sortedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }

        let input = zip(testRunners, sortedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: $0.0.testRunner) })
    }()

    init(configuration: Configuration, testTarget: String, productNames: [String], sdk: XcodeProject.SDK, failingTestsRetryCount: Int, testTimeoutSeconds: Int, xcresultBlobThresholdKB: Int?, verbose: Bool) {
        self.configuration = configuration
        self.testTarget = testTarget
        self.productNames = productNames
        self.sdk = sdk
        self.failingTestsRetryCount = failingTestsRetryCount
        self.testTimeoutSeconds = testTimeoutSeconds
        self.verbose = verbose
        self.xcresultBlobThresholdKB = xcresultBlobThresholdKB
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            var result = currentResult ?? [TestCaseResult]()

            testCasesCount = sortedTestCases?.count ?? 0
            guard testCasesCount > 0 else {
                didEnd?(result)
                return
            }

            if !result.isEmpty {
                print("\n\nℹ️  Repeating failing tests".magenta)
            }

            try pool.execute { [unowned self] executer, source in
                let testRunner = source.value

                let runnerIndex = self.syncQueue.sync { [unowned self] in self.testRunners?.firstIndex { $0.0.id == testRunner.id && $0.0.name == testRunner.name } ?? 0 }
                
                while true {
                    let testCases: [TestCase] = self.syncQueue.sync { [unowned self] in
                        guard let testCase = self.sortedTestCases?.first else {
                            return []
                        }

                        self.sortedTestCases?.removeFirst()

                        return [testCase]
                    }

                    guard !testCases.isEmpty else { break }

                    if self.verbose {
                        if testCases.count == 1 {
                            print("🚦  [\(Date().description)] Node \(source.node.address) will execute \(testCases[0].description) on \(testRunner.name) {\(runnerIndex)}".magenta)
                        } else {
                            print("🚦  [\(Date().description)] Node \(source.node.address) will execute \(testCases.count) tests on \(testRunner.name) {\(runnerIndex)}".magenta)
                        }
                    }

                    executer.logger?.log(command: "Will launch \(testCases.count) test cases")
                    executer.logger?.log(output: testCases.map(\.testIdentifier).joined(separator: "\n"), statusCode: 0)
                    
                    try autoreleasepool {
                        var (output, testResults) = try self.testWithoutBuilding(executer: executer, node: source.node.address, testTarget: self.testTarget, testCases: testCases, testRunner: testRunner, runnerIndex: runnerIndex)

                        let xcResultUrl = try self.findTestResultUrl(executer: executer, testRunner: testRunner)

                        // We need to move results because xcodebuild test-without-building shows a weird behaviour not allowing more than 2 xcresults in the same folder.
                        // Repeatedly performing 'xcodebuild test-without-building' results in older xcresults being deleted
                        let resultUrl = Path.results.url.appendingPathComponent(testRunner.id)
                        _ = try executer.capture("mkdir -p '\(resultUrl.path)'; mv '\(xcResultUrl.path)' '\(resultUrl.path)'")
                        for index in 0..<testResults.count {
                            testResults[index].xcResultPath = resultUrl.path
                        }
                                                
                        if let bootstrappingTestResults = try self.handleBootstrappingErrors(output, partialResult: testResults, candidates: testCases, node: source.node.address, runnerName: testRunner.name, runnerIdentifier: testRunner.id, xcResultPath: xcResultUrl.path) {
                            testResults += bootstrappingTestResults

                            self.forceResetSimulator(executer: executer, testRunner: testRunner)
                        }

                        self.syncQueue.sync { [unowned self] in
                            for test in self.testsToRetry(testResults: testResults, testCases: testCases, failingTestsRetryCount: self.failingTestsRetryCount) {
                                if self.sortedTestCases?.count == 0 {
                                    self.sortedTestCases?.append(test)
                                } else {
                                    // By inserting at index 1 we make sure that the test will likely be retried on a different simulator
                                    self.sortedTestCases?.insert(test, at: 1)
                                }
                            }

                            result += testResults
                        }
                    }
                    
                    // We need to progressively merge coverage results since everytime we launch a test a brand new coverage file is created
                    
                    let searchPath = Path.logs.url.appendingPathComponent(testRunner.id).path
                    let coverageMerger = CodeCoverageMerger(executer: executer, searchPath: searchPath)
                    
                    let start = CFAbsoluteTimeGetCurrent()
                    _ = try? coverageMerger.merge()
                    if self.verbose {
                        print("🙈 [\(Date().description)] Node \(source.node.address) took \(CFAbsoluteTimeGetCurrent() - start)s for coverage merge {\(runnerIndex)}".magenta)
                    }
                }

                try self.copyDiagnosticReports(executer: executer, testRunner: testRunner)

                try self.reclaimDiskSpace(executer: executer, testRunner: testRunner)
                                
                print("\nℹ️  Node {\(runnerIndex)} did execute tests in \(hoursMinutesSeconds(in: CFAbsoluteTimeGetCurrent() - self.startTimeInterval))\n".magenta)
            }

            didEnd?(result)
        } catch {
            didThrow?(error)
        }
    }

    override func cancel() {
        if isExecuting {
            pool.terminate()
        }
        super.cancel()
    }

    private func testWithoutBuilding(executer: Executer, node: String, testTarget: String, testCases: [TestCase], testRunner: TestRunner, runnerIndex: Int) throws -> (output: String, testCaseResults: [TestCaseResult]) {
        let testRun = try findTestRun(executer: executer)
        let onlyTesting = testCases.map { "-only-testing:'\(testTarget)/\($0.testIdentifier)'" }.joined(separator: " ")
        let destinationPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        
        var testCaseResults = [TestCaseResult]()

        var testWithoutBuilding: String

        switch sdk {
        case .ios:
            testWithoutBuilding = #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination 'platform=iOS Simulator,id=\#(testRunner.id)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -destination-timeout 60 -test-timeouts-enabled YES -maximum-test-execution-time-allowance \#(testTimeoutSeconds) test-without-building"#
        case .macos:
            testWithoutBuilding = #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination 'platform=OS X,arch=x86_64' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -test-timeouts-enabled YES -maximum-test-execution-time-allowance \#(testTimeoutSeconds) test-without-building"#
        }
        testWithoutBuilding += " || true"

        var parsedProgress = ""
        var partialProgress = ""
        let progressHandler: ((String) -> Void) = { [unowned self] progress in
            parsedProgress += progress
            partialProgress += progress
            let lines = partialProgress.components(separatedBy: "\n")
            let events = lines.compactMap(self.parseXcodebuildOutput)

            for (index, event) in events.enumerated() {
                switch event {
                case let .testStart(testCase):
                    self.syncQueue.sync {
                        self.currentRunningTest[runnerIndex] = (test: testCase, start: CFAbsoluteTimeGetCurrent())

                        if self.verbose { print("🛫 [\(Date().description)] \(testCase.description) started {\(runnerIndex)}".yellow) }
                    }
                case .testPassed:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = self.currentRunningTest[runnerIndex] else { return }
                        defer { self.currentRunningTest[runnerIndex] = nil }
                        
                        let testCaseResult = TestCaseResult(node: node, runnerName: testRunner.name, runnerIdentifier: testRunner.id, xcResultPath: "-", suite: currentRunning.test.suite, name: currentRunning.test.name, status: .passed, startInterval: currentRunning.start, endInterval: CFAbsoluteTimeGetCurrent())
                        testCaseResults.append(testCaseResult)
                        
                        self.testCasesCompletedCount += 1
                        print("✅ \(self.verbose ? "[\(Date().description)] " : "")\(currentRunning.test.description) passed [\(self.testCasesCompletedCount)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(Int(testCaseResult.duration.rounded(.up)))s {\(runnerIndex)}".green)
                    }
                case .testFailed, .testCrashed, .testTimedOut:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = self.currentRunningTest[runnerIndex] else { return }
                        defer { self.currentRunningTest[runnerIndex] = nil }
                        
                        let addToCompleted = index > 0 ? events[index - 1].isTestCrashed == false : true

                        let testCaseResult = TestCaseResult(node: node, runnerName: testRunner.name, runnerIdentifier: testRunner.id, xcResultPath: "-", suite: currentRunning.test.suite, name: currentRunning.test.name, status: .failed, startInterval: currentRunning.start, endInterval: CFAbsoluteTimeGetCurrent())
                        if addToCompleted {
                            testCaseResults.append(testCaseResult)
                        }
                        
                        self.testCasesCompletedCount += 1
                        if case .testCrashed = event {
                            print("💣 \(self.verbose ? "[\(Date().description)] " : "")\(currentRunning.test.description) crashed [\(self.testCasesCompletedCount)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(Int(testCaseResult.duration.rounded(.up)))s {\(runnerIndex)}".red)
                        } else if case .testCrashed = event {
                            print("⏲ \(self.verbose ? "[\(Date().description)] " : "")\(currentRunning.test.description) timed out [\(self.testCasesCompletedCount)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(Int(testCaseResult.duration.rounded(.up)))s {\(runnerIndex)}".red)
                        } else {
                            print("❌ \(self.verbose ? "[\(Date().description)] " : "")\(currentRunning.test.description) failed [\(self.testCasesCompletedCount)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(Int(testCaseResult.duration.rounded(.up)))s {\(runnerIndex)}".red)
                        }
                    }
                case .noSpaceOnDevice:
                    fatalError("💣 No space left on \(executer.address). If you're using a RAM disk in Mendoza's configuration consider increasing size")
                }
            }

            partialProgress = lines.last ?? ""
        }
        
        let testResultsUrls = try findTestResultsUrl(executer: executer, testRunner: testRunner)
        try testResultsUrls.forEach { _ = try executer.execute("rm -rf '\($0.path)' || true") }
                
        var output = try executer.execute(testWithoutBuilding, progress: progressHandler) { result, originalError in
            try self.assertAccessibilityPermissions(in: result.output)
            if !self.shouldIgnoreTestExecutionError(originalError) {
                throw originalError
            }
        }
        
        // It should be rare but it may happen that stdout content is not processed in the partailBlock
        output = (output + "\n").replacingOccurrences(of: parsedProgress, with: "")
        progressHandler(output)
        
        // xcodebuild returns 0 even on ** TEST EXECUTE FAILED ** when missing
        // accessibility permissions or other errors like the bootstrapping once we check in testsDidFailToStart
        try assertAccessibilityPermissions(in: output)
        
        if testsDidFailBootstrapping(in: output) {
            Thread.sleep(forTimeInterval: 10.0)
        }
        
        if testDidFailBecauseOfDamagedBuild(in: output) {
            switch AddressType(address: executer.address) {
            case .local:
                _ = try executer.execute("rm -rf '\(Path.build.rawValue)' || true")
                // To be improved
                throw Error("Tests failed because of damaged build folder, please try rerunning the build again")
            case .remote:
                break
            }
        }
        
        if testDidFailLoadingAccessibility(in: output) {
            self.forceResetSimulator(executer: executer, testRunner: testRunner)
        }

        return (output: output, testCaseResults: testCaseResults)
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

            let testCase = TestCase(name: testCaseName, suite: testCaseSuite)

            return .testStart(testCase: testCase)
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

    private func handleBootstrappingErrors(_ output: String, partialResult: [TestCaseResult], candidates: [TestCase], node: String, runnerName: String, runnerIdentifier: String, xcResultPath: String) throws -> [TestCaseResult]? {
        let boostrappingError = "Application failed preflight checks"

        let resultPath = xcResultPath.replacingOccurrences(of: "\(Path.logs.rawValue)/", with: "")

        if output.contains(boostrappingError) {
            let failedCandidates = candidates.filter { candidate in
                partialResult.contains(where: { candidate.suite == $0.suite && candidate.testIdentifier == $0.testCaseIdentifier }) == false
            }
            
            let startInterval: TimeInterval = CFAbsoluteTimeGetCurrent()
            let endInterval: TimeInterval = startInterval - 1.0

            return failedCandidates.map { TestCaseResult(node: node, runnerName: runnerName, runnerIdentifier: runnerIdentifier, xcResultPath: resultPath, suite: $0.suite, name: $0.name, status: .failed, startInterval: startInterval, endInterval: endInterval) }
        }

        return nil
    }

    private func forceResetSimulator(executer: Executer, testRunner: TestRunner) {
        guard let simulatorExecuter = try? executer.clone() else { return }

        let proxy = CommandLineProxy.Simulators(executer: simulatorExecuter, verbose: true)
        let simulator = Simulator(id: testRunner.id, name: "Simulator", device: Device.defaultInit())

        // There's no better option than shutting down simulator at this point
        // xcodebuild will take care to boot simulator again and continue testing
        try? proxy.shutdown(simulator: simulator)
    }

    private func testsToRetry(testResults: [TestCaseResult], testCases: [TestCase], failingTestsRetryCount: Int) -> [TestCase] {
        let failedTestCases = testResults.filter { $0.status == .failed }.map { TestCase(name: $0.name, suite: $0.suite) }

        var testToRetry = [TestCase]()
        for failedTestCase in failedTestCases {
            if retryCountMap.count(for: failedTestCase) < failingTestsRetryCount {
                retryCountMap.add(failedTestCase)
                testToRetry.insert(failedTestCase, at: 0)
                testCasesCount += 1

                if verbose {
                    print("🔁  Renqueuing \(failedTestCase), retry count: \(retryCountMap.count(for: failedTestCase))".yellow)
                }
            }
        }
        
        // We should reenqueue all tests that were scheduled (testCases) but were not included in results (testResults). While uncommon it can happen in some rare cases
        for testCase in testCases {
            if !testResults.contains(where: { $0.testCaseIdentifier == testCase.testIdentifier }) {
                testToRetry.insert(testCase, at: 0)
            }
        }

        return testToRetry
    }

    private func findTestRun(executer: Executer) throws -> String {
        let testBundlePath = Path.testBundle.rawValue

        let testRuns = try executer.execute("find '\(testBundlePath)' -type f -name '\(configuration.scheme)*.xctestrun'").components(separatedBy: "\n")
        guard let testRun = testRuns.first, !testRun.isEmpty else { throw Error("No test bundle found", logger: executer.logger) }
        guard testRuns.count == 1 else { throw Error("Too many xctestrun bundles found:\n\(testRuns)", logger: executer.logger) }

        return testRun
    }

    private func findTestResultUrl(executer: Executer, testRunner: TestRunner) throws -> URL {
        let testResults = try findTestResultsUrl(executer: executer, testRunner: testRunner)
        guard let testResult = testResults.first else { throw Error("No test result found", logger: executer.logger) }
        guard testResults.count == 1 else { throw Error("Too many test results found", logger: executer.logger) }

        return testResult
    }

    private func findTestResultsUrl(executer: Executer, testRunner: TestRunner) throws -> [URL] {
        let resultPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        let testResults = (try? executer.execute("find '\(resultPath)' -type d -name '*.xcresult'").components(separatedBy: "\n")) ?? []

        return testResults.filter { $0.isEmpty == false }.map { URL(fileURLWithPath: $0) }
    }

    private func copyDiagnosticReports(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("DiagnosticReports").path

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        
        for productName in productNames {
            let sourcePath = "~/Library/Logs/DiagnosticReports/\(productName)_*"
            _ = try executer.execute("cp '\(sourcePath)' \(destinationPath) || true")
        }
    }
    
    private func reclaimDiskSpace(executer: Executer, testRunner: TestRunner) throws {
        guard let xcresultBlobThresholdKB = xcresultBlobThresholdKB else { return }
        
        let testRunnerLogUrl = Path.results.url.appendingPathComponent(testRunner.id)
        let minSizeParam = "-size +\(xcresultBlobThresholdKB)k"
        
        let sourcePaths = try executer.execute(#"find \#(testRunnerLogUrl.path) -type f -regex '.*/.*\.xcresult/.*' \#(minSizeParam)"#).components(separatedBy: "\n").filter { $0.isEmpty == false  }
        
        for sourcePath in sourcePaths {
            _ = try executer.execute(#"echo "content replaced by mendoza because original file was larger than \#(xcresultBlobThresholdKB)KB" > '\#(sourcePath)'"#)
        }
    }

    private func assertAccessibilityPermissions(in output: String) throws {
        if output.contains("does not have permission to use Accessibility") {
            throw Error("Unable to run UI Tests because Xcode Helper does not have permission to use Accessibility. To enable UI testing, go to the Security & Privacy pane in System Preferences, select the Privacy tab, then select Accessibility, and add Xcode Helper to the list of applications allowed to use Accessibility")
        }
    }

    private func testsDidFailBootstrapping(in output: String) -> Bool {
        output.contains("Test runner exited before starting test execution")
    }
    
    private func testDidFailLoadingAccessibility(in output: String) -> Bool {
        output.contains("has not loaded accessibility")
    }

    private func testDidFailBecauseOfDamagedBuild(in output: String) -> Bool {
        output.contains("The application may be damaged or incomplete")
    }
}
