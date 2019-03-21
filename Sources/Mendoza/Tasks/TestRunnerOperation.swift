//
//  TestRunnerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestRunnerOperation: BaseOperation<[TestCaseResult]> {
    var distributedTestCases: [[TestCase]]?
    var simulators: [(simulator: Simulator, node: Node)]?
    
    private let configuration: Configuration
    private let buildTarget: String
    private let testTarget: String
    private let sdk: XcodeProject.SDK
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    
    private lazy var pool: ConnectionPool<(Simulator, [TestCase])> = {
        guard let distributedTestCases = distributedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let simulators = simulators else { fatalError("💣 Required field `simulator` not set") }
        guard simulators.count >= distributedTestCases.count else { fatalError("💣 Invalid simulator count") }

        let input = zip(simulators, distributedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: ($0.0.simulator, $0.1)) })
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
                let simulator = source.value.0
                let testCases = source.value.1
                
                guard testCases.count > 0 else { return }
                
                print("ℹ️  Node \(source.node.address) will execute \(testCases.count) tests on \(simulator.name)".magenta)
                
                executer.logger?.log(command: "Will launch \(testCases.count) test cases")
                executer.logger?.log(output: testCases.map { $0.testIdentifier }.joined(separator: "\n"), statusCode: 0)
                
                let testRun = try self.findTestRun(executer: executer)
                let onlyTesting = testCases.map { "-only-testing:\(self.configuration.scheme)/\($0.testIdentifier)" }.joined(separator: " ")
                let destinationPath = Path.logs.url.appendingPathComponent(simulator.id).path
                
                var testWithoutBuilding: String
                    
                switch self.sdk {
                case .ios:
                    testWithoutBuilding = #"xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun \#(testRun) -destination 'platform=iOS TestRunner,id=\#(testRunner.id)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES test-without-building"#
                case .macos:
                    #warning("TODO")
                    testWithoutBuilding = #"xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun \#(testRun) -destination 'platform=iOS TestRunner,id=\#(testRunner.id)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES test-without-building"#
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
                
                let output = try executer.execute(testWithoutBuilding, progress: progressHandler)
                
                let summaryPlistUrl = try self.findTestSummaryPlistUrl(executer: executer, simulator: simulator)
                let testResults = try self.parseTestResults(output, candidates: testCases, node: source.node.address, summaryPlistPath: summaryPlistUrl.path)
                self.syncQueue.sync { result += testResults }

                try self.copyDiagnosticReports(executer: executer, summaryPlistUrl: summaryPlistUrl, simulator: simulator)
                try self.copyStandardOutputLogs(executer: executer, simulator: simulator)
                try self.copySessionLogs(executer: executer, simulator: simulator)
                
                try self.reclaimDiskSpace(executer: executer, simulator: simulator)
                
                #if DEBUG
                    print("ℹ️  Node \(source.node.address) did execute tests on \(simulator.name)".magenta)
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
    
    private func findTestSummaryPlistUrl(executer: Executer, simulator: Simulator) throws -> URL {
        let resultPath = Path.logs.url.appendingPathComponent(simulator.id).path
        let testResults = try executer.execute("find '\(resultPath)' -type f -name 'TestSummaries.plist'").components(separatedBy: "\n")
        guard let testResult = testResults.first, testResult.count > 0 else { throw Error("No test result found", logger: executer.logger) }
        guard testResults.count == 1 else { throw Error("Too many test results found", logger: executer.logger) }

        return URL(fileURLWithPath: testResult)
    }
    
    private func copyDiagnosticReports(executer: Executer, summaryPlistUrl: URL, simulator: Simulator) throws {
        let sourcePath1 = "~/Library/Logs/DiagnosticReports/\(buildTarget)*"
        let sourcePath2 = "~/Library/Logs/DiagnosticReports/\(testTarget)*"
        
        let simulatorLogUrl = Path.logs.url.appendingPathComponent(simulator.id)
        let destinationPath = simulatorLogUrl.appendingPathComponent("DiagnosticReports").path
        
        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        _ = try executer.execute("cp '\(sourcePath1)' \(destinationPath) || true")
        _ = try executer.execute("cp '\(sourcePath2)' \(destinationPath) || true")
    }
    
    private func copyStandardOutputLogs(executer: Executer, simulator: Simulator) throws {
        let simulatorLogUrl = Path.logs.url.appendingPathComponent(simulator.id)
        let destinationPath = simulatorLogUrl.appendingPathComponent("StandardOutputAndStandardError").path
        let sourcePaths = try executer.execute("find \(simulatorLogUrl.path) -name 'StandardOutputAndStandardError*.txt'").components(separatedBy: "\n")
        
        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)'") }
    }

    private func copySessionLogs(executer: Executer, simulator: Simulator) throws {
        let simulatorLogUrl = Path.logs.url.appendingPathComponent(simulator.id)
        let destinationPath = simulatorLogUrl.appendingPathComponent("Session").path
        let sourcePaths = try executer.execute("find \(simulatorLogUrl.path) -name 'Session-\(testTarget)*.log'").components(separatedBy: "\n")
        
        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)'") }
    }
    
    private func reclaimDiskSpace(executer: Executer, simulator: Simulator) throws {
        // remove all Diagnostiscs folder inside .xcresult which contain some largish log files we don't need
        let simulatorLogUrl = Path.logs.url.appendingPathComponent(simulator.id)
        var sourcePaths = try executer.execute("find \(simulatorLogUrl.path) -type d -name 'Diagnostics'").components(separatedBy: "\n")
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
}
