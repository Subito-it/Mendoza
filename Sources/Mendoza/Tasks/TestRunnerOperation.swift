//
//  TestRunnerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestRunnerOperation: BaseOperation<[TestCaseResult]> {
    var distributedTestCases: [[TestCase]]?
    var testRunners: [(testRunner: TestRunner, node: Node)]? // TODO: rename to destinations
    
    private let configuration: Configuration
    private let buildTarget: String
    private let testTarget: String
    private let sdk: XcodeProject.SDK
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    
    private lazy var pool: ConnectionPool<(TestRunner, [TestCase])> = {
        guard let distributedTestCases = distributedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }
        guard testRunners.count >= distributedTestCases.count else { fatalError("💣 Invalid testRunner count") }

        let input = zip(testRunners, distributedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: ($0.0.testRunner, $0.1)) })
    }()
    
    init(configuration: Configuration, buildTarget: String, testTarget: String, sdk: XcodeProject.SDK) {
        self.configuration = configuration
        self.buildTarget = buildTarget
        self.testTarget = testTarget
        self.sdk = sdk
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            var result = [TestCaseResult]()
            
            let testCasesCount = distributedTestCases?.reduce(0, { $0 + $1.count }) ?? 0
            var completedCount = 0
            
            try pool.execute { [unowned self] (executer, source) in
                let testRunner = source.value.0
                let testCases = source.value.1
                
                guard testCases.count > 0 else { return }
                
                print("ℹ️  Node \(source.node.address) will execute \(testCases.count) tests on \(testRunner.name)".magenta)
                
                executer.logger?.log(command: "Will launch \(testCases.count) test cases")
                executer.logger?.log(output: testCases.map { $0.testIdentifier }.joined(separator: "\n"), statusCode: 0)
                
                let testRun = try self.findTestRun(executer: executer)
                let onlyTesting = testCases.map { "-only-testing:\(self.configuration.scheme)/\($0.testIdentifier)" }.joined(separator: " ")
                let destinationPath = Path.logs.url.appendingPathComponent(testRunner.id).path
                
                var testWithoutBuilding: String
                    
                switch self.sdk {
                case .ios:
                    testWithoutBuilding = #"xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun \#(testRun) -destination 'platform=iOS Simulator,id=\#(testRunner.id)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -destination-timeout 60 test-without-building"#
                case .macos:
                    testWithoutBuilding = #"xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun \#(testRun) -destination 'platform=OS X,arch=x86_64' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES test-without-building"#
                }
                testWithoutBuilding += " || true"
                
                var partialProgress = ""
                let progressHandler: ((String) -> Void) = { progress in
                    partialProgress += progress
                    let lines = partialProgress.components(separatedBy: "\n")
                    
                    for line in lines.dropLast() { // last line might not be completely received
                        let regex = #"Test Case '-\[\#(self.testTarget)\.(.*)\]' (passed|failed)"#
                        if let tests = try? line.capturedGroups(withRegexString: regex), tests.count == 2 {
                            self.syncQueue.sync {
                                completedCount += 1
                                
                                if tests[1] == "passed" {
                                    print("✓ \(tests[0]) passed [\(completedCount)/\(testCasesCount)]".green)
                                } else {
                                    print("𝘅 \(tests[0]) failed [\(completedCount)/\(testCasesCount)]".red)
                                }
                            }
                        }
                    }
                    
                    partialProgress = lines.last ?? ""
                }
                
                let output = try executer.execute(testWithoutBuilding, progress: progressHandler) { result, originalError in
                    try self.assertAccessibilityPermissiong(in: result.output)
                    throw originalError
                }
                // xcodebuild returns 0 even on ** TEST EXECUTE FAILED ** when missing accessibility
                try self.assertAccessibilityPermissiong(in: output)
                
                let summaryPlistUrl = try self.findTestSummaryPlistUrl(executer: executer, testRunner: testRunner)
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
    
    private func findTestRun(executer: Executer) throws -> String {
        let testBundlePath = Path.testBundle.rawValue
        
        let testRuns = try executer.execute("find '\(testBundlePath)' -type f -name '*.xctestrun'").components(separatedBy: "\n")
        guard let testRun = testRuns.first, testRun.count > 0 else { throw Error("No test bundle found", logger: executer.logger) }
        guard testRuns.count == 1 else { throw Error("Too many xctestrun bundles found:\n\(testRuns)", logger: executer.logger) }

        return testRun
    }
    
    private func findTestSummaryPlistUrl(executer: Executer, testRunner: TestRunner) throws -> URL {
        let resultPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        let testResults = try executer.execute("find '\(resultPath)' -type f -name 'TestSummaries.plist'").components(separatedBy: "\n")
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
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)'") }
    }

    private func copySessionLogs(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("Session").path
        let sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -name 'Session-\(testTarget)*.log'").components(separatedBy: "\n")
        
        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)'") }
    }
    
    private func reclaimDiskSpace(executer: Executer, testRunner: TestRunner) throws {
        // remove all Diagnostiscs folder inside .xcresult which contain some largish log files we don't need
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        var sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -type d -name 'Diagnostics'").components(separatedBy: "\n")
        sourcePaths = sourcePaths.filter { $0.contains(".xcresult/") }
        
        try sourcePaths.forEach { _ = try executer.execute(#"rm -rf "\#($0)""#) }
    }

    private func parseTestResults(_ output: String, candidates: [TestCase], node: String, summaryPlistPath: String) throws -> [TestCaseResult] {
        let filteredOutput = output.components(separatedBy: "\n").filter { $0.hasPrefix("Test Case") }

        var result = [TestCaseResult]()
        var mCandidates = candidates
        for line in filteredOutput {
            for (index, candidate) in mCandidates.enumerated() {
                if line.contains("\(testTarget).\(candidate.suite) \(candidate.name)") {
                    let outputResult = try line.capturedGroups(withRegexString: #"(passed|failed) \((.*) seconds\)"#)
                    if outputResult.count == 2 {
                        let duration: Double = Double(outputResult[1]) ?? -1.0
                        let plistPath = summaryPlistPath.replacingOccurrences(of: "\(Path.logs.rawValue)/", with: "")
                        let testCaseResults = TestCaseResult(node: node, summaryPlistPath: plistPath, suite: candidate.suite, name: candidate.name, status: outputResult[0] == "passed" ? .passed : .failed, duration: duration)
                        result.append(testCaseResults)
                        mCandidates.remove(at: index)
                        break
                    }
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
}
