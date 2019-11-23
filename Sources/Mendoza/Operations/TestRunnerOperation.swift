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
    private let testTimeoutSeconds: Int
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private let verbose: Bool
    private var timeoutBlocks = [Int: CancellableDelayedTask]()
    private var maxTestsPerIteration = 0
    
    private enum XcodebuildLineEvent {
        case testStart(testCase: TestCase)
        case testPassed(duration: Double)
        case testFailed(duration: Double)
        case testCrashed
        
        var isTestPassed: Bool { switch self { case .testPassed: return true; default: return false } }
    }
    
    private lazy var pool: ConnectionPool<TestRunner> = {
        guard let sortedTestCases = sortedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }
        
        let input = zip(testRunners, sortedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: $0.0.testRunner) })
    }()
    
    init(configuration: Configuration, buildTarget: String, testTarget: String, sdk: XcodeProject.SDK, testTimeoutSeconds: Int, verbose: Bool) {
        self.configuration = configuration
        self.buildTarget = buildTarget
        self.testTarget = testTarget
        self.sdk = sdk
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
            maxTestsPerIteration = max(1, testCasesCount / ((testRunners?.count ?? 1) * 2))
            
            if result.count > 0 {
                print("\n\nℹ️  Repeating failing tests".magenta)
            }
            
            try pool.execute { [unowned self] (executer, source) in
                let testRunner = source.value
                
                let runnerIndex = self.syncQueue.sync { [unowned self] in self.testRunners?.firstIndex { $0.0.id == testRunner.id && $0.0.name == testRunner.name } ?? 0 }
                
                while true {
                    // If the sorting plugin is installed, test cases are sorted by execution time with longest coming first.
                    // we enqueue tests from available test cases stepping by the total number of runners. This way long test
                    // are spread an executed on all runners.
                    let testCases: [TestCase] = self.syncQueue.sync { [unowned self] in
                        var testCases = [TestCase]()
                        let totalRunners = self.testRunners?.count ?? 1
                        
                        let sortedTestCases = self.sortedTestCases ?? []
                        
                        for (index, testCase) in sortedTestCases.enumerated() {
                            if index % totalRunners == runnerIndex {
                                testCases.append(testCase)
                                if testCases.count == self.maxTestsPerIteration {
                                    break
                                }
                            }
                        }
                        
                        self.sortedTestCases?.removeAll(where: { testCases.contains($0) })
                        
                        return testCases
                    }
                    
                    guard testCases.count > 0 else { break }
                    
                    print("ℹ️  Node \(source.node.address) will execute \(testCases.count) tests on \(testRunner.name) {\(runnerIndex)}".magenta)
                    
                    executer.logger?.log(command: "Will launch \(testCases.count) test cases")
                    executer.logger?.log(output: testCases.map { $0.testIdentifier }.joined(separator: "\n"), statusCode: 0)
                    
                    let output = try autoreleasepool {
                        return try self.testWithoutBuilding(executer: executer, testCases: testCases, testRunner: testRunner, runnerIndex: runnerIndex)
                    }
                    
                    let xcResultUrl = try self.findTestResultUrl(executer: executer, testRunner: testRunner)
                    
                    // We need to move results because xcodebuild test-without-building shows a weird behaviour not allowing more than 2 xcresults in the same folder.
                    // Repeatedly performing 'xcodebuild test-without-building' results in older xcresults being deleted
                    let resultUrl = Path.results.url.appendingPathComponent(testRunner.id)
                    _ = try executer.capture("mkdir -p '\(resultUrl.path)'; mv '\(xcResultUrl.path)' '\(resultUrl.path)'")
                    
                    let testResults = try self.parseTestResults(output, candidates: testCases, node: source.node.address, xcResultPath: xcResultUrl.path)
                    self.syncQueue.sync { result += testResults }
                }
                
                try self.copyDiagnosticReports(executer: executer, testRunner: testRunner)
                try self.copyStandardOutputLogs(executer: executer, testRunner: testRunner)
                try self.copySessionLogs(executer: executer, testRunner: testRunner)
                
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
    
    private func testWithoutBuilding(executer: Executer, testCases: [TestCase], testRunner: TestRunner, runnerIndex: Int) throws -> String {
        let testRun = try findTestRun(executer: executer)
        let onlyTesting = testCases.map { "-only-testing:\(configuration.scheme)/\($0.testIdentifier)" }.joined(separator: " ")
        let destinationPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        
        var testWithoutBuilding: String
        
        switch sdk {
        case .ios:
            testWithoutBuilding = #"xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun \#(testRun) -destination 'platform=iOS Simulator,id=\#(testRunner.id)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -destination-timeout 60 test-without-building"#
        case .macos:
            testWithoutBuilding = #"xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun \#(testRun) -destination 'platform=OS X,arch=x86_64' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES test-without-building"#
        }
        testWithoutBuilding += " || true"
        
        var partialProgress = ""
        let progressHandler: ((String) -> Void) = { [unowned self] progress in
            let timeoutBlockRunning = self.syncQueue.sync { self.timeoutBlocks[runnerIndex]?.isRunning == true }
            guard !timeoutBlockRunning else {
                return
            }
            
            self.syncQueue.sync {
                self.timeoutBlocks[runnerIndex]?.cancel()
                self.timeoutBlocks[runnerIndex] = self.makeTimeoutBlock(executer: executer, currentRunning: self.currentRunningTest[runnerIndex], testRunner: testRunner, runnerIndex: runnerIndex)
            }
            
            partialProgress += progress
            let lines = partialProgress.components(separatedBy: "\n")
            let events = lines.compactMap(self.parseXcodebuildOutput)
            
            let currentRunningAndDuration: () -> (test: TestCase, duration: String)? = {
                guard let currentRunning = self.currentRunningTest[runnerIndex] else { return nil }
                
                if !self.testCasesCompleted.contains(currentRunning.test) {
                    self.testCasesCompleted.append(currentRunning.test)
                }
                
                let duration = hoursMinutesSeconds(in: CFAbsoluteTimeGetCurrent() - currentRunning.start)
                
                return (test: currentRunning.test, duration: duration)
            }
            
            for event in events {
                switch event {
                case let .testStart(testCase):
                    self.syncQueue.sync {
                        self.currentRunningTest[runnerIndex] = (test: testCase, start: CFAbsoluteTimeGetCurrent())
                        
                        if self.verbose { print("🛫 [\(Date().description)] \(testCase.description) started {\(runnerIndex)}".yellow) }
                    }
                case .testPassed:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = currentRunningAndDuration() else { return }
                        self.currentRunningTest[runnerIndex] = nil
                        
                        print("✓ \(self.verbose ? "[\(Date().description)]" : "")\(currentRunning.test.description) passed [\(self.testCasesCompleted.count)/\(self.testCasesCount)] in \(currentRunning.duration) {\(runnerIndex)}".green)
                    }
                case .testFailed:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = currentRunningAndDuration() else { return }
                        self.currentRunningTest[runnerIndex] = nil
                        
                        print("𝘅 \(self.verbose ? "[\(Date().description)]" : "")\(currentRunning.test.description) failed [\(self.testCasesCompleted.count)/\(self.testCasesCount)] in \(currentRunning.duration) {\(runnerIndex)}".green)
                    }
                case .testCrashed:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = currentRunningAndDuration() else { return }
                        self.currentRunningTest[runnerIndex] = nil
                        
                        print("💥 \(self.verbose ? "[\(Date().description)]" : "")\(currentRunning.test.description) crash [\(self.testCasesCompleted.count)/\(self.testCasesCount)] in \(currentRunning.duration) {\(runnerIndex)}".green)
                    }
                }
            }
            
            partialProgress = lines.last ?? ""
        }
                
        var output = ""
        for shouldRetry in [true, false] {
            output = try executer.execute(testWithoutBuilding, progress: progressHandler) { result, originalError in
                try self.assertAccessibilityPermissiong(in: result.output)
                throw originalError
            }
            
            syncQueue.sync { timeoutBlocks[runnerIndex]?.cancel() }
            
            // xcodebuild returns 0 even on ** TEST EXECUTE FAILED ** when missing
            // accessibility permissions or other errors like the bootstrapping onese we check in testsDidFailToStart
            try self.assertAccessibilityPermissiong(in: output)
            
            guard !testsDidFailBootstrapping(in: output) else {
                Thread.sleep(forTimeInterval: 5.0)
                partialProgress = ""
                
                guard shouldRetry else {
                    throw Error("Tests failed boostrapping on node \(testRunner.name)-\(testRunner.id)")
                }
                
                continue
            }
            
            guard !testDidFailBecauseOfDamagedBuild(in: output) else {
                switch AddressType(address: executer.address) {
                case .local:
                    _ = try executer.execute("rm -rf '\(Path.build.rawValue)' || true")
                    // To be improved
                    throw Error("Tests failed because of damaged build folder, please try rerunning the build again")
                case .remote:
                    break
                }
                
                break
            }
            
            break
        }
        
        return output
    }
    
    private func parseXcodebuildOutput(line: String) -> XcodebuildLineEvent? {
        let testResultCrashMarker1 = #"Restarting after unexpected exit or crash in (.*)/(.*)\(\)"#
        let testResultCrashMarker2 = #"\s+(.*)\(\) encountered an error \(Crash:"#
        let testResultCrashMarker3 = #"Checking for crash reports corresponding to unexpected termination of"#
        
        let startRegex = #"Test Case '-\[\#(self.testTarget)\.(.*)\]' started"#
        
        if let tests = try? line.capturedGroups(withRegexString: startRegex), tests.count == 1 {
            let testCaseName = tests[0].components(separatedBy: " ").last ?? ""
            let testCaseSuite = tests[0].components(separatedBy: " ").first ?? ""
            
            let testCase = TestCase(name: testCaseName, suite: testCaseSuite)
            
            return .testStart(testCase: testCase)
        }
        
        let passFailRegex = #"Test Case '-\[\#(self.testTarget)\.(.*)\]' (passed|failed) \((.*) seconds\)"#
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
        
        if line.contains(testResultCrashMarker3) {
            return .testCrashed
        }
        
        return nil
    }
    
    private func parseTestResults(_ output: String, candidates: [TestCase], node: String, xcResultPath: String) throws -> [TestCaseResult] {
        let resultPath = xcResultPath.replacingOccurrences(of: "\(Path.logs.rawValue)/", with: "")
        
        var result = [TestCaseResult]()
        
        let lines = output.components(separatedBy: "\n")
        let events = lines.compactMap(self.parseXcodebuildOutput)
        
        var currentCandidate: TestCase?
        
        for event in events {
            switch event {
            case let .testStart(test):
                guard let matchingCandidate = candidates.first(where: { $0 == test }) else {
                    if verbose { print("⚠️  did not find test results for `\(test.description)`\n") }
                    break
                }
                
                currentCandidate = matchingCandidate
            case .testPassed(let duration), .testFailed(let duration):
                guard let currentCandidate =  currentCandidate else { break }
                
                let testCaseResults = TestCaseResult(node: node, xcResultPath: resultPath, suite: currentCandidate.suite, name: currentCandidate.name, status: event.isTestPassed ? .passed : .failed, duration: duration)
                if let index = result.firstIndex(where: { $0 == testCaseResults }) {
                    result.remove(at: index) // Remove crash result if previously added
                }
                result.append(testCaseResults)
            case .testCrashed:
                guard let currentCandidate =  currentCandidate else { break }
                
                let testCaseResults = TestCaseResult(node: node, xcResultPath: resultPath, suite: currentCandidate.suite, name: currentCandidate.name, status: .failed, duration: -1)
                result.append(testCaseResults)
            }
        }
        
        return result
    }
    
    private func makeTimeoutBlock(executer: Executer, currentRunning: (test: TestCase, start: TimeInterval)?, testRunner: TestRunner, runnerIndex: Int) -> CancellableDelayedTask {
        let task = CancellableDelayedTask(delay: TimeInterval(testTimeoutSeconds), queue: syncQueue)
        
        task.run {
            guard let simulatorExecuter = try? executer.clone() else {
                return
            }
            
            if let currentRunning = currentRunning {
                print("⏰ \(currentRunning.test.description) timed out {\(runnerIndex)} in \(Int(CFAbsoluteTimeGetCurrent() - currentRunning.start))s".red)
            } else {
                print("⏰ Unknown test timed out {\(runnerIndex)}".red)
            }
            
            let proxy = CommandLineProxy.Simulators(executer: simulatorExecuter, verbose: true)
            let simulator = Simulator(id: testRunner.id, name: "Simulator", device: Device.defaultInit())
            
            // There's no better option than shutting down simulator at this point
            // xcodebuild will take care to boot simulator again and continue testing
            try? proxy.shutdown(simulator: simulator)
            try? proxy.boot(simulator: simulator)
        }
        
        return task
    }
    
    private func findTestRun(executer: Executer) throws -> String {
        let testBundlePath = Path.testBundle.rawValue
        
        let testRuns = try executer.execute("find '\(testBundlePath)' -type f -name '\(configuration.scheme)*.xctestrun'").components(separatedBy: "\n")
        guard let testRun = testRuns.first, testRun.count > 0 else { throw Error("No test bundle found", logger: executer.logger) }
        guard testRuns.count == 1 else { throw Error("Too many xctestrun bundles found:\n\(testRuns)", logger: executer.logger) }
        
        return testRun
    }
    
    private func findTestResultUrl(executer: Executer, testRunner: TestRunner) throws -> URL {
        let resultPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        let testResults = try executer.execute("find '\(resultPath)' -type d -name '*.xcresult'").components(separatedBy: "\n")
        guard let testResult = testResults.first, testResult.count > 0 else { throw Error("No test result found", logger: executer.logger) }
        guard testResults.count == 1 else { throw Error("Too many test results found", logger: executer.logger) }
        
        return URL(fileURLWithPath: testResult)
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
    
    private func assertAccessibilityPermissiong(in output: String) throws {
        if output.contains("does not have permission to use Accessibility") {
            throw Error("Unable to run UI Tests because Xcode Helper does not have permission to use Accessibility. To enable UI testing, go to the Security & Privacy pane in System Preferences, select the Privacy tab, then select Accessibility, and add Xcode Helper to the list of applications allowed to use Accessibility")
        }
    }
    
    private func testsDidFailBootstrapping(in output: String) -> Bool {
        return output.contains("Test runner exited before starting test execution")
    }
    
    private func testDidFailBecauseOfDamagedBuild(in output: String) -> Bool {
        return output.contains("The application may be damaged or incomplete")
    }
}
