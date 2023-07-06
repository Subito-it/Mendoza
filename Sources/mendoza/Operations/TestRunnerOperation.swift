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
    var testRunners: [(testRunner: TestRunner, node: Node, idle: Bool)]?

    private var testCasesCount = 0
    private var testCasesCompletedCount = 0

    private let testExecuterBuilder: (Executer, TestCase, Node, TestRunner, Int) -> TestExecuter

    private let productNames: [String]
    private let failingTestsRetryCount: Int
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private let verbose: Bool
    private var retryCountMap = NSCountedSet()
    private var retryCount: Int { // access only from syncQueue
        retryCountMap.reduce(0) { $0 + retryCountMap.count(for: $1) }
    }

    private let xcresultBlobThresholdKB: Int?

    private let configuration: Configuration
    private let destinationPath: String

    private let postExecutionQueue = ThreadQueue()

    private lazy var pool: ConnectionPool<TestRunner> = {
        guard let sortedTestCases = sortedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }

        let input = zip(testRunners, sortedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: $0.0.testRunner) })
    }()

    init(configuration: Configuration, destinationPath: String, testTarget: String, productNames: [String], sdk: XcodeProject.SDK, failingTestsRetryCount: Int, maximumStdOutIdleTime: Int?, maximumTestExecutionTime: Int?, xcresultBlobThresholdKB: Int?, verbose: Bool) {
        testExecuterBuilder = { executer, testCase, node, testRunner, runnerIndex in
            TestExecuter(executer: executer, testCase: testCase, testTarget: testTarget, configuration: configuration, sdk: sdk, maximumStdOutIdleTime: maximumStdOutIdleTime, maximumTestExecutionTime: maximumTestExecutionTime, node: node, testRunner: testRunner, runnerIndex: runnerIndex, verbose: verbose)
        }

        self.productNames = productNames
        self.failingTestsRetryCount = failingTestsRetryCount
        self.verbose = verbose
        self.xcresultBlobThresholdKB = xcresultBlobThresholdKB
        self.configuration = configuration
        self.destinationPath = destinationPath
    }

    enum State {
        case execute(TestCase)
        case waitingCompletion // no new tests to execute, but waiting for potential retries of tests running on other active runners runners to complete
        case allRunnersCompleted // all runners completed, disptach ended
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            var result = [TestCaseResult]()

            testCasesCount = sortedTestCases?.count ?? 0
            guard testCasesCount > 0 else {
                didEnd?(result)
                return
            }

            if !result.isEmpty {
                print("\n\nℹ️  Repeating failing tests".magenta)
            }

            try pool.execute { [weak self] executer, source in
                guard let self = self else { return }

                let testRunner = source.value
                let runnerIndex = self.runnerIndex(for: testRunner)

                defer { self.syncQueue.sync { self.testRunners?[runnerIndex].idle = true } }

                while true {
                    var testCase: TestCase!
                    var allRunnersCompleted = false

                    self.syncQueue.sync {
                        if let nextTestCase = self.nextTestCase() {
                            testCase = nextTestCase
                        } else {
                            allRunnersCompleted = self.testRunners?.allSatisfy(\.idle) == true
                        }

                        if let testRunnerIndex = self.testRunners?.firstIndex(where: { $0.node == source.node && $0.testRunner.id == testRunner.id && $0.testRunner.name == testRunner.name }) {
                            self.testRunners?[testRunnerIndex].idle = testCase == nil
                        }
                    }

                    if testCase == nil {
                        if allRunnersCompleted {
                            break
                        } else {
                            Thread.sleep(forTimeInterval: 1.0)
                            continue
                        }
                    }

                    var testCaseResult: TestCaseResult?

                    try autoreleasepool {
                        let testResultsUrls = try self.findTestResultsUrl(executer: executer, testRunner: testRunner)
                        for path in testResultsUrls.map(\.path) {
                            guard path.hasPrefix(Path.base.rawValue) else { continue }
                            _ = try executer.execute("rm -rf '\(path)' || true")
                        }

                        let testExecuter = self.testExecuterBuilder(executer, testCase, source.node, testRunner, runnerIndex)
                        var xcodebuildOutput = ""
                        (xcodebuildOutput, testCaseResult) = try testExecuter.launch { previewTestCaseResult in
                            self.handleTestCaseResultPreview(previewTestCaseResult, testCase: testCase, runnerIndex: runnerIndex)

                            self.syncQueue.sync { self.testCasesCompletedCount += 1 }
                        }

                        // Inspect output for failures that require additional
                        if self.testDidFailLoadingAccessibility(in: xcodebuildOutput) {
                            self.forceResetSimulator(executer: executer, testRunner: testRunner)
                        }

                        // xcodebuild returns 0 even on ** TEST EXECUTE FAILED ** when missing
                        // accessibility permissions or other errors like the bootstrapping once we check in testsDidFailToStart
                        try self.assertAccessibilityPermissions(in: xcodebuildOutput)

                        if self.testsDidFailBootstrapping(in: xcodebuildOutput) {
                            Thread.sleep(forTimeInterval: 10.0)
                        }

                        if self.testDidFailPreflightChecks(in: xcodebuildOutput) {
                            self.forceResetSimulator(executer: executer, testRunner: testRunner)
                        }

                        if self.testDidFailBecauseOfDamagedBuild(in: xcodebuildOutput) {
                            switch AddressType(address: executer.address) {
                            case .local:
                                _ = try executer.execute("rm -rf '\(Path.build.rawValue)' || true")
                                // To be improved
                                throw Error("Tests failed because of damaged build folder, please try rerunning the build again")
                            case .remote:
                                break
                            }
                        }

                        if let xcResultUrl = try self.findTestResultUrl(executer: executer, testRunner: testRunner) {
                            // We need to move results because xcodebuild test-without-building shows a weird behaviour not allowing more than 2 xcresults in the same folder.
                            // Repeatedly performing 'xcodebuild test-without-building' results in older xcresults being deleted
                            let resultUrl = Path.results.url.appendingPathComponent(testRunner.id)
                            _ = try executer.capture("mkdir -p '\(resultUrl.path)'; mv '\(xcResultUrl.path)' '\(resultUrl.path)'")
                            testCaseResult?.xcResultPath = resultUrl.appendingPathComponent(xcResultUrl.lastPathComponent).path
                        }

                        if let testCaseResult = testCaseResult {
                            self.syncQueue.sync { result += [testCaseResult] }
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

                    let destinationNode = self.configuration.resultDestination.node

                    let groupExecuter = try executer.clone()
                    let logger = ExecuterLogger(name: (executer.logger?.name ?? "") + "-async", address: executer.logger?.address ?? "")
                    groupExecuter.logger = logger

                    self.addLogger(logger)

                    self.postExecutionQueue.addOperation {
                        guard let xcResultPath = testCaseResult?.xcResultPath, xcResultPath.hasPrefix(Path.base.rawValue) else { return }

                        let runnerDestinationPath = "\(self.destinationPath)/\(testRunner.id)"
                        try? groupExecuter.rsync(sourcePath: xcResultPath, destinationPath: runnerDestinationPath, on: destinationNode)

                        _ = try? groupExecuter.execute("rm -rf '\(xcResultPath)'")
                    }
                }

                try self.copyDiagnosticReports(executer: executer, testRunner: testRunner)
            }

            postExecutionQueue.waitUntilAllOperationsAreFinished()

            didEnd?(result)
        } catch {
            didThrow?(error)
        }
    }

    private func handleTestCaseResultPreview(_ testCaseResult: TestCaseResult, testCase: TestCase, runnerIndex: Int) {
        syncQueue.sync {
            switch testCaseResult.status {
            case .passed:
                print("✅ \(self.verbose ? "[\(Date().description)] " : "")\(testCase.description) passed [\(self.testCasesCompletedCount + 1)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(Int(testCaseResult.duration.rounded(.up)))s {\(runnerIndex)}".green)
            case .failed:
                print("❌ \(self.verbose ? "[\(Date().description)] " : "")\(testCase.description) failed [\(self.testCasesCompletedCount + 1)/\(self.testCasesCount)]\(self.retryCount > 0 ? " (\(self.retryCount) retries)" : "") in \(Int(testCaseResult.duration.rounded(.up)))s {\(runnerIndex)}".red)

                let shouldRetryTest = retryCountMap.count(for: testCase) < failingTestsRetryCount
                if shouldRetryTest {
                    testCasesCount += 1
                    retryCountMap.add(testCase)

                    if self.sortedTestCases?.isEmpty == true {
                        self.sortedTestCases?.append(testCase)
                    } else {
                        // By inserting at index 1 we make sure that the test will likely be retried on a different simulator
                        self.sortedTestCases?.insert(testCase, at: 1)
                    }

                    if verbose {
                        print("🔁  Renqueuing (no result) \(testCase), retry count: \(retryCountMap.count(for: testCase))".yellow)
                    }
                }
            }
        }
    }

    override func cancel() {
        if isExecuting {
            pool.terminate()
        }
        super.cancel()
    }

    private func runnerIndex(for testRunner: TestRunner) -> Int {
        syncQueue.sync { [unowned self] in self.testRunners?.firstIndex { $0.0.id == testRunner.id && $0.0.name == testRunner.name } ?? 0 }
    }

    private func nextTestCase() -> TestCase? {
        // This method should be called from syncQueue
        guard let testCase = sortedTestCases?.first else {
            return nil
        }

        sortedTestCases?.removeFirst()

        return testCase
    }
}

private extension TestRunnerOperation {
    func findTestResultUrl(executer: Executer, testRunner: TestRunner) throws -> URL? {
        let testResults = try findTestResultsUrl(executer: executer, testRunner: testRunner)
        guard let testResult = testResults.first else {
            // Under certain failures xcodebuild does not produce an .xcresult
            return nil
        }
        guard testResults.count == 1 else { throw Error("Too many test results found", logger: executer.logger) }

        return testResult
    }

    func findTestResultsUrl(executer: Executer, testRunner: TestRunner) throws -> [URL] {
        let resultPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        let testResults = (try? executer.execute("find '\(resultPath)' -type d -name '*.xcresult'").components(separatedBy: "\n")) ?? []

        return testResults.filter { $0.isEmpty == false }.map { URL(fileURLWithPath: $0) }
    }
}

private extension TestRunnerOperation {
    func copyDiagnosticReports(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("DiagnosticReports").path

        _ = try executer.execute("mkdir -p '\(destinationPath)'")

        for productName in productNames {
            let sourcePath = "~/Library/Logs/DiagnosticReports/\(productName)_*"
            _ = try executer.execute("cp '\(sourcePath)' \(destinationPath) || true")
        }
    }

    func reclaimDiskSpace(executer: Executer, testRunner _: TestRunner, path: String) throws {
        guard let xcresultBlobThresholdKB = xcresultBlobThresholdKB else { return }

        let minSizeParam = "-size +\(xcresultBlobThresholdKB)k"

        let sourcePaths = try executer.execute(#"find \#(path) -type f -regex '.*/.*\.xcresult/.*' \#(minSizeParam)"#).components(separatedBy: "\n").filter { $0.isEmpty == false }

        for sourcePath in sourcePaths {
            _ = try executer.execute(#"echo "content replaced by mendoza because original file was larger than \#(xcresultBlobThresholdKB)KB" > '\#(sourcePath)'"#)
        }
    }

    private func forceResetSimulator(executer: Executer, testRunner: TestRunner) {
        guard let simulatorExecuter = try? executer.clone() else { return }

        let proxy = CommandLineProxy.Simulators(executer: simulatorExecuter, verbose: true)
        let simulator = Simulator(id: testRunner.id, name: "Simulator", device: Device.defaultInit())

        // There's no better option than shutting down simulator at this point
        // xcodebuild will take care to boot simulator again and continue testing
        try? proxy.shutdown(simulator: simulator)
    }
}

private extension TestRunnerOperation {
    func assertAccessibilityPermissions(in output: String) throws {
        if output.contains("does not have permission to use Accessibility") {
            throw Error("Unable to run UI Tests because Xcode Helper does not have permission to use Accessibility. To enable UI testing, go to the Security & Privacy pane in System Preferences, select the Privacy tab, then select Accessibility, and add Xcode Helper to the list of applications allowed to use Accessibility")
        }
    }

    func testDidFailPreflightChecks(in output: String) -> Bool {
        output.contains("Application failed preflight checks")
    }

    func testsDidFailBootstrapping(in output: String) -> Bool {
        output.contains("Test runner exited before starting test execution")
    }

    func testDidFailLoadingAccessibility(in output: String) -> Bool {
        output.contains("has not loaded accessibility")
    }

    func testDidFailBecauseOfDamagedBuild(in output: String) -> Bool {
        output.contains("The application may be damaged or incomplete")
    }
}
