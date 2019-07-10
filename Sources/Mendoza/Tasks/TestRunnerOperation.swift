//
//  TestRunnerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestRunnerOperation: BaseOperation<[TestCaseResult]> {
    var distributedTestCases: [[TestCase]]? {
        didSet {
            testCasesCount = distributedTestCases?.reduce(0, { $0 + $1.count }) ?? 0
        }
    }
    var currentResult: [TestCaseResult]?
    var testRunners: [(testRunner: TestRunner, node: Node)]?
    
    private var testCasesCount = 0
    private var completedCount = 0
    
    private let configuration: Configuration
    private let buildTarget: String
    private let testTarget: String
    private let sdk: XcodeProject.SDK
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private let verbose: Bool
    
    private lazy var pool: ConnectionPool<(TestRunner, [TestCase])> = {
        guard let distributedTestCases = distributedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }
        guard testRunners.count >= distributedTestCases.count else { fatalError("💣 Invalid testRunner count") }

        let input = zip(testRunners, distributedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: ($0.0.testRunner, $0.1)) })
    }()
    
    init(configuration: Configuration, buildTarget: String, testTarget: String, sdk: XcodeProject.SDK, verbose: Bool) {
        self.configuration = configuration
        self.buildTarget = buildTarget
        self.testTarget = testTarget
        self.sdk = sdk
        self.verbose = verbose
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            var result = currentResult ?? [TestCaseResult]()
            
            guard distributedTestCases?.contains(where: { $0.count > 0 }) == true else {
                didEnd?(result)
                return
            }
            
            if result.count > 0 {
                print("\nℹ️  Repeating failing tests\n".magenta)
            }

            try pool.execute { [unowned self] (executer, source) in
                let testRunner = source.value.0
                let testCases = source.value.1
                
                guard testCases.count > 0 else { return }
                
                print("ℹ️  Node \(source.node.address) will execute \(testCases.count) tests on \(testRunner.name)".magenta)
                
                executer.logger?.log(command: "Will launch \(testCases.count) test cases")
                executer.logger?.log(output: testCases.map { $0.testIdentifier }.joined(separator: "\n"), statusCode: 0)
                
                let output = try self.testWithoutBuilding(executer: executer, testCases: testCases, testRunner: testRunner)
                
                let xcResultUrl = try self.findTestResultUrl(executer: executer, testRunner: testRunner)
                
                // We need to move results for 2 reasons that occurr when retrying to execute failing tests
                // 1. to ensure that findTestSummariesUrl only finds 1 result
                // 2. xcodebuild test-without-building shows a weird behaviour not allowing more than 2 xcresults in the same folder. Repeatedly performing 'xcodebuild test-without-building' results in older xcresults being deleted
                let resultUrl = Path.results.url.appendingPathComponent(testRunner.id)
                _ = try executer.capture("mkdir -p '\(resultUrl.path)'; mv '\(xcResultUrl.path)' '\(resultUrl.path)'")
                
                let basePath = resultUrl.appendingPathComponent(xcResultUrl.lastPathComponent).path
                let summaryPlistUrl = try self.findTestSummariesUrl(executer: executer, basePath: basePath)
                
                let testResults = try self.parseTestResults(output, candidates: testCases, node: source.node.address, summaryPlistPath: summaryPlistUrl.path)
                self.syncQueue.sync { result += testResults }

                try self.copyDiagnosticReports(executer: executer, summaryPlistUrl: summaryPlistUrl, testRunner: testRunner)
                try self.copyStandardOutputLogs(executer: executer, testRunner: testRunner)
                try self.copySessionLogs(executer: executer, testRunner: testRunner)

                try self.reclaimDiskSpace(executer: executer, testRunner: testRunner)

                #if DEBUG
                    print("ℹ️  Node \(source.node.address) did execute tests on \(testRunner.name)".magenta)
                #endif
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
    
    private func testWithoutBuilding(executer: Executer, testCases: [TestCase], testRunner: TestRunner) throws -> String {
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
            partialProgress += progress
            let lines = partialProgress.components(separatedBy: "\n")
            
            for line in lines.dropLast() { // last line might not be completely received
                let regex = #"Test Case '-\[\#(self.testTarget)\.(.*)\]' (passed|failed)"#
                if let tests = try? line.capturedGroups(withRegexString: regex), tests.count == 2 {
                    self.syncQueue.sync { [unowned self] in
                        self.completedCount += 1
                        
                        if tests[1] == "passed" {
                            print("✓ \(tests[0]) passed [\(self.completedCount)/\(self.testCasesCount)]".green)
                        } else {
                            print("𝘅 \(tests[0]) failed [\(self.completedCount)/\(self.testCasesCount)]".red)
                        }
                    }
                }
                
                let crashRegex = #"Restarting after unexpected exit or crash in (.*)/(.*)"#
                if let tests = try? line.capturedGroups(withRegexString: crashRegex), tests.count == 2 {
                    self.syncQueue.sync { [unowned self] in
                        self.completedCount += 1
                        
                        print("𝘅 \(tests[0]) \(tests[1]) failed [\(self.completedCount)/\(self.testCasesCount)]".red)
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
    
    private func findTestSummariesUrl(executer: Executer, basePath: String) throws -> URL {
        let testResults = try executer.execute("find '\(basePath)' -type f -name 'TestSummaries.plist'").components(separatedBy: "\n")
        guard let testResult = testResults.first, testResult.count > 0 else { throw Error("No test result found", logger: executer.logger) }
        guard testResults.count == 1 else { throw Error("Too many test results found", logger: executer.logger) }
        
        return URL(fileURLWithPath: testResult)
    }
    
    private func copyDiagnosticReports(executer: Executer, summaryPlistUrl: URL, testRunner: TestRunner) throws {
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

    private func parseTestResults(_ output: String, candidates: [TestCase], node: String, summaryPlistPath: String) throws -> [TestCaseResult] {
        let filteredOutput = output.components(separatedBy: "\n").filter { $0.hasPrefix("Test Case") }

        let plistPath = summaryPlistPath.replacingOccurrences(of: "\(Path.results.rawValue)/", with: "")
        
        var result = [TestCaseResult]()
        var mCandidates = candidates
        for line in filteredOutput {
            for (index, candidate) in mCandidates.enumerated() {
                if line.contains("\(testTarget).\(candidate.suite) \(candidate.name)") {
                    let outputResult = try line.capturedGroups(withRegexString: #"(passed|failed) \((.*) seconds\)"#)
                    if outputResult.count == 2 {
                        let duration: Double = Double(outputResult[1]) ?? -1.0
                        
                        let testCaseResults = TestCaseResult(node: node, summaryPlistPath: plistPath, suite: candidate.suite, name: candidate.name, status: outputResult[0] == "passed" ? .passed : .failed, duration: duration)
                        result.append(testCaseResults)
                        mCandidates.remove(at: index)
                        
                        break
                    }
                } else if line.contains("Restarting after unexpected exit or crash in \(candidate.suite)/\(candidate.name)") {
                    let duration: Double = -1.0

                    let testCaseResults = TestCaseResult(node: node, summaryPlistPath: plistPath, suite: candidate.suite, name: candidate.name, status: .failed, duration: duration)
                    result.append(testCaseResults)
                    mCandidates.remove(at: index)
                    
                    break
                }
            }
        }
        
        if mCandidates.count > 0 {
            let missingTestCases = mCandidates.map { $0.testIdentifier }.joined(separator: ", ")
            #if DEBUG
                print("⚠️  did not find test results for `\(missingTestCases)`")
            #endif
        }
        
        return result
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
