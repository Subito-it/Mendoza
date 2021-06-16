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
    private var testCasesCompleted = [TestCase]()

    private let configuration: Configuration
    private let buildTarget: String
    private let testTarget: String
    private let sdk: XcodeProject.SDK
    private let failingTestsRetryCount: Int
    private let testTimeoutSeconds: Int
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private let verbose: Bool
    private var retryCountMap = NSCountedSet()
    private var retryCount: Int { // access only from syncQueue
        retryCountMap.reduce(0) { $0 + retryCountMap.count(for: $1) }
    }

    private enum XcodebuildLineEvent {
        case testStart(testCase: TestCase)
        case testPassed(duration: Double)
        case testFailed(duration: Double)
        case testCrashed
        case noSpaceOnDevice

        var isTestPassed: Bool { switch self { case .testPassed: return true; default: return false } } // swiftlint:disable:this switch_case_alignment
        var isTestCrashed: Bool { switch self { case .testCrashed: return true; default: return false } } // swiftlint:disable:this switch_case_alignment
    }

    private lazy var pool: ConnectionPool<TestRunner> = {
        guard let sortedTestCases = sortedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }

        let input = zip(testRunners, sortedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: $0.0.testRunner) })
    }()

    init(configuration: Configuration, buildTarget: String, testTarget: String, sdk: XcodeProject.SDK, failingTestsRetryCount: Int, testTimeoutSeconds: Int, verbose: Bool) {
        self.configuration = configuration
        self.buildTarget = buildTarget
        self.testTarget = testTarget
        self.sdk = sdk
        self.failingTestsRetryCount = failingTestsRetryCount
        self.testTimeoutSeconds = testTimeoutSeconds
        self.verbose = verbose
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
                
                let group = DispatchGroup()
                let codeCoverageMergeQueue = DispatchQueue(label: "com.subito.mendoza.coverage.merge")

                while true {
                    let testCases: [TestCase] = self.syncQueue.sync { [unowned self] in
                        guard let testCase = self.sortedTestCases?.first else {
                            return []
                        }

                        self.sortedTestCases?.removeFirst()

                        return [testCase]
                    }

                    guard !testCases.isEmpty else { break }

                    print("ℹ️  \(self.verbose ? "[\(Date().description)] " : "")Node \(source.node.address) will execute \(testCases.count) tests on \(testRunner.name) {\(runnerIndex)}".magenta)

                    executer.logger?.log(command: "Will launch \(testCases.count) test cases")
                    executer.logger?.log(output: testCases.map(\.testIdentifier).joined(separator: "\n"), statusCode: 0)

                    let output = try autoreleasepool {
                        try self.testWithoutBuilding(executer: executer, testTarget: self.testTarget, testCases: testCases, testRunner: testRunner, runnerIndex: runnerIndex)
                    }

                    let xcResultUrl = try self.findTestResultUrl(executer: executer, testRunner: testRunner)

                    // We need to move results because xcodebuild test-without-building shows a weird behaviour not allowing more than 2 xcresults in the same folder.
                    // Repeatedly performing 'xcodebuild test-without-building' results in older xcresults being deleted
                    let resultUrl = Path.results.url.appendingPathComponent(testRunner.id)
                    _ = try executer.capture("mkdir -p '\(resultUrl.path)'; mv '\(xcResultUrl.path)' '\(resultUrl.path)'")

                    var testResults = try self.parseTestResults(output, candidates: testCases, node: source.node.address, xcResultPath: xcResultUrl.path)

                    if let bootstrappingTestResults = try self.handleBootstrappingErrors(output, partialResult: testResults, candidates: testCases, node: source.node.address, xcResultPath: xcResultUrl.path) {
                        testResults += bootstrappingTestResults

                        self.forceResetSimulator(executer: executer, testRunner: testRunner)
                    }

                    self.syncQueue.sync { [unowned self] in
                        self.enqueueFailedTests(testResults: testResults, failingTestsRetryCount: self.failingTestsRetryCount).forEach { self.sortedTestCases?.insert($0, at: 0) }

                        result += testResults
                    }
                    
                    // We need to progressively merge coverage results since everytime we launch a test a brand new coverage file is created
                    
                    let logger = ExecuterLogger(name: "Coverage merge", address: source.node.address)
                    let executer = try source.node.makeExecuter(logger: logger)
                    let searchPath = Path.logs.url.appendingPathComponent(testRunner.id).path
                    let coverageMerger = CodeCoverageMerger(executer: executer, searchPath: searchPath)
                    
                    group.enter()
                    codeCoverageMergeQueue.async {
                        _ = try? coverageMerger.merge()
                        group.leave()
                    }
                }

                try self.copyDiagnosticReports(executer: executer, testRunner: testRunner)
                try self.copyStandardOutputLogs(executer: executer, testRunner: testRunner)
                try self.copySessionLogs(executer: executer, testRunner: testRunner)

                try self.reclaimDiskSpace(executer: executer, testRunner: testRunner)
                
                if group.wait(timeout: .now() + 30.0) == .timedOut {
                    print("\nℹ️  Node {\(runnerIndex)} code coverage merge failed")
                }

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

    private func testWithoutBuilding(executer: Executer, testTarget: String, testCases: [TestCase], testRunner: TestRunner, runnerIndex: Int) throws -> String {
        let testRun = try findTestRun(executer: executer)
        let onlyTesting = testCases.map { "-only-testing:'\(testTarget)/\($0.testIdentifier)'" }.joined(separator: " ")
        let destinationPath = Path.logs.url.appendingPathComponent(testRunner.id).path

        var testWithoutBuilding: String

        switch sdk {
        case .ios:
            testWithoutBuilding = #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination 'platform=iOS Simulator,id=\#(testRunner.id)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -destination-timeout 60 -test-timeouts-enabled YES -maximum-test-execution-time-allowance \#(testTimeoutSeconds) test-without-building"#
        case .macos:
            testWithoutBuilding = #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination 'platform=OS X,arch=x86_64' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -test-timeouts-enabled YES -maximum-test-execution-time-allowance \#(testTimeoutSeconds) test-without-building"#
        }
        testWithoutBuilding += " || true"

        var partialProgress = ""
        let progressHandler: ((String) -> Void) = { [unowned self] progress in
            partialProgress += progress
            let lines = partialProgress.components(separatedBy: "\n")
            let events = lines.compactMap(self.parseXcodebuildOutput)

            let currentRunningAndDuration: (Bool) -> (test: TestCase, duration: String)? = { [unowned self] addToCompleted in
                guard let currentRunning = self.currentRunningTest[runnerIndex] else { return nil }

                if addToCompleted {
                    self.testCasesCompleted.append(currentRunning.test)
                }

                let duration = hoursMinutesSeconds(in: CFAbsoluteTimeGetCurrent() - currentRunning.start)

                return (test: currentRunning.test, duration: duration)
            }

            for (index, event) in events.enumerated() {
                switch event {
                case let .testStart(testCase):
                    self.syncQueue.sync {
                        self.currentRunningTest[runnerIndex] = (test: testCase, start: CFAbsoluteTimeGetCurrent())

                        if self.verbose { print("🛫 [\(Date().description)] \(testCase.description) started {\(runnerIndex)}".yellow) }
                    }
                case .testPassed:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = currentRunningAndDuration(true) else { return }
                        self.currentRunningTest[runnerIndex] = nil

                        print("✓ \(self.verbose ? "[\(Date().description)] " : "")\(currentRunning.test.description) passed [\(self.testCasesCompleted.count)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(currentRunning.duration) {\(runnerIndex)}".green)
                    }
                case .testFailed:
                    self.syncQueue.sync { [unowned self] in
                        let addToCompleted = index > 0 ? events[index - 1].isTestCrashed == false : true

                        if let currentRunning = currentRunningAndDuration(addToCompleted) {
                        self.currentRunningTest[runnerIndex] = nil

                        print("𝘅 \(self.verbose ? "[\(Date().description)] " : "")\(currentRunning.test.description) failed [\(self.testCasesCompleted.count)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(currentRunning.duration) {\(runnerIndex)}".red)
                        } else {
                            let failedTests = testCases.map(\.testIdentifier).joined(separator: " ")
                            
                            print("𝘅 \(self.verbose ? "[\(Date().description)] " : "")\(failedTests) failed [\(self.testCasesCompleted.count)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") {\(runnerIndex)}".red)
                        }
                    }
                case .testCrashed:
                    self.syncQueue.sync { [unowned self] in
                        if let currentRunning = currentRunningAndDuration(true) {
                        self.currentRunningTest[runnerIndex] = nil

                            print("💥 \(self.verbose ? "[\(Date().description)] " : "")\(currentRunning.test.description) crashed [\(self.testCasesCompleted.count)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(currentRunning.duration) {\(runnerIndex)}".red)
                        } else {
                            let crashedTests = testCases.map(\.testIdentifier).joined(separator: " ")
                            
                            print("💥 \(self.verbose ? "[\(Date().description)] " : "")\(crashedTests) crashed [\(self.testCasesCompleted.count)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") {\(runnerIndex)}".red)
                        }
                    }
                case .noSpaceOnDevice:
                    fatalError("💥  No space left on \(executer.address). If you're using a RAM disk in Mendoza's configuration consider increasing size")
                }
            }

            partialProgress = lines.last ?? ""
        }
        
        let testResults = try findTestResultsUrl(executer: executer, testRunner: testRunner)
        try testResults.forEach { _ = try executer.execute("rm -rf '\($0.path)' || true") }
        
        let output = try executer.execute(testWithoutBuilding, progress: progressHandler) { result, originalError in
            try self.assertAccessibilityPermissions(in: result.output)
            throw originalError
        }
        
        // xcodebuild returns 0 even on ** TEST EXECUTE FAILED ** when missing
        // accessibility permissions or other errors like the bootstrapping onese we check in testsDidFailToStart
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

        return output
    }

    private func parseXcodebuildOutput(line: String) -> XcodebuildLineEvent? {
        let testResultCrashMarker1 = #"Restarting after unexpected exit or crash in (.*)/(.*)\(\)"#
        let testResultCrashMarker2 = #"\s+(.*)\(\) encountered an error \(Crash:"#
        let testResultCrashMarker3 = #"Checking for crash reports corresponding to unexpected termination of"#
        let testResultTimeoutMarker4 = #"\s+(.*)\(\) encountered an error \(Test runner exited"# // Should be caused by the force reset of simulator
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

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker1), tests.count == 2 {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker2), tests.count == 1 {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultTimeoutMarker4), tests.count == 1 {
            return .testFailed(duration: -1)
        }

        if line.contains(testResultCrashMarker3) {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultFailureMarker1), tests.count == 1 {
            return .testFailed(duration: -1)
        }

        return nil
    }

    private func parseTestResults(_ output: String, candidates: [TestCase], node: String, xcResultPath: String) throws -> [TestCaseResult] {
        let resultPath = xcResultPath.replacingOccurrences(of: "\(Path.logs.rawValue)/", with: "")

        var result = [TestCaseResult]()

        let lines = output.components(separatedBy: "\n")
        let events = lines.compactMap(parseXcodebuildOutput)

        var currentCandidate: TestCase?

        for event in events {
            switch event {
            case let .testStart(test):
                guard let matchingCandidate = candidates.first(where: { $0 == test }) else {
                    if verbose { print("⚠️  did not find test results for `\(test.description)`\n") }
                    break
                }

                currentCandidate = matchingCandidate
            case let .testPassed(duration), let .testFailed(duration):
                guard let currentCandidate = currentCandidate else { break }

                let testCaseResults = TestCaseResult(node: node, xcResultPath: resultPath, suite: currentCandidate.suite, name: currentCandidate.name, status: event.isTestPassed ? .passed : .failed, duration: duration)
                if let index = result.firstIndex(where: { $0 == testCaseResults }) {
                    result.remove(at: index) // Remove crash result if previously added
                }
                result.append(testCaseResults)
            case .testCrashed:
                guard let currentCandidate = currentCandidate else { break }

                let testCaseResults = TestCaseResult(node: node, xcResultPath: resultPath, suite: currentCandidate.suite, name: currentCandidate.name, status: .failed, duration: -1)
                result.append(testCaseResults)
            case .noSpaceOnDevice:
                throw Error("💥  No space left on device. If you're using a RAM disk in Mendoza's configuration consider increasing size".red)
            }
        }

        return result
    }

    private func handleBootstrappingErrors(_ output: String, partialResult: [TestCaseResult], candidates: [TestCase], node: String, xcResultPath: String) throws -> [TestCaseResult]? {
        let boostrappingError = "Application failed preflight checks"

        let resultPath = xcResultPath.replacingOccurrences(of: "\(Path.logs.rawValue)/", with: "")

        if output.contains(boostrappingError) {
            let failedCandidates = candidates.filter { candidate in
                partialResult.contains(where: { candidate.suite == $0.suite && candidate.testIdentifier == $0.testCaseIdentifier }) == false
            }

            return failedCandidates.map { TestCaseResult(node: node, xcResultPath: resultPath, suite: $0.suite, name: $0.name, status: .failed, duration: -1) }
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

    private func enqueueFailedTests(testResults: [TestCaseResult], failingTestsRetryCount: Int) -> [TestCase] {
        let failedTestCases = testResults.filter { $0.status == .failed }.map { TestCase(name: $0.name, suite: $0.suite) }

        var testCases = [TestCase]()
        for failedTestCase in failedTestCases {
            if retryCountMap.count(for: failedTestCase) < failingTestsRetryCount {
                retryCountMap.add(failedTestCase)
                testCases.insert(failedTestCase, at: 0)
                testCasesCount += 1

                if verbose {
                    print("🔁  Renqueuing \(failedTestCase), retry count: \(retryCountMap.count(for: failedTestCase))".yellow)
                }
            }
        }

        return testCases
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
        let sourcePath1 = "~/Library/Logs/DiagnosticReports/\(buildTarget)*"
        let sourcePath2 = "~/Library/Logs/DiagnosticReports/\(testTarget)*"

        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("DiagnosticReports").path

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        _ = try executer.execute("cp '\(sourcePath1)' \(destinationPath) || true")
        _ = try executer.execute("cp '\(sourcePath2)' \(destinationPath) || true")
    }

    private func copyStandardOutputLogs(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("StandardOutputAndStandardError").path
        let sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -name 'StandardOutputAndStandardError*.txt'").components(separatedBy: "\n")

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)' || true") }
    }

    private func copySessionLogs(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("Session").path
        let sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -name 'Session-\(testTarget)*.log'").components(separatedBy: "\n")

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)' || true") }
    }

    private func reclaimDiskSpace(executer: Executer, testRunner: TestRunner) throws {
        // remove all Diagnostiscs folder inside .xcresult which contain some largish log files we don't need
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        var sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -type d -name 'Diagnostics'").components(separatedBy: "\n")
        sourcePaths = sourcePaths.filter { $0.contains(".xcresult/") }

        try sourcePaths.forEach {
            print(#"rm -rf "\#($0)"#)
            _ = try executer.execute(#"rm -rf "\#($0)""#)
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
