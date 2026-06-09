//
//  TestCaseExecutor.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Orchestrates the execution of a single test case including cleanup, execution,
/// output analysis, result handling, coverage, and post-execution tasks
class TestCaseExecutor {
    typealias TestExecuterBuilder = (Executer, TestCase, Node, TestRunner, Int) -> TestExecuter
    typealias PreviewHandler = (TestCaseResult) -> Void

    private let configuration: Configuration
    private let testExecuterBuilder: TestExecuterBuilder
    private let xcResultHandler: XCResultHandler
    private let outputAnalyzer: OutputAnalyzer
    private let coverageHandler: CoverageHandler
    private let simulatorRecovery: SimulatorRecovery
    private let postExecutionHandler: PostExecutionHandler
    private let postExecutionQueue: ThreadQueue
    private let addLogger: (ExecuterLogger) -> Void

    private let asyncLoggersQueue = DispatchQueue(label: "com.subito.mendoza.testCaseExecutor.asyncLoggers")
    private var idleAsyncLoggers = [String: [ExecuterLogger]]()
    private var asyncLoggerCounts = [String: Int]()

    init(
        configuration: Configuration,
        testExecuterBuilder: @escaping TestExecuterBuilder,
        xcResultHandler: XCResultHandler,
        outputAnalyzer: OutputAnalyzer,
        coverageHandler: CoverageHandler,
        simulatorRecovery: SimulatorRecovery,
        postExecutionHandler: PostExecutionHandler,
        postExecutionQueue: ThreadQueue,
        addLogger: @escaping (ExecuterLogger) -> Void
    ) {
        self.configuration = configuration
        self.testExecuterBuilder = testExecuterBuilder
        self.xcResultHandler = xcResultHandler
        self.outputAnalyzer = outputAnalyzer
        self.coverageHandler = coverageHandler
        self.simulatorRecovery = simulatorRecovery
        self.postExecutionHandler = postExecutionHandler
        self.postExecutionQueue = postExecutionQueue
        self.addLogger = addLogger
    }

    /// Execute a single test case
    /// - Parameters:
    ///   - testCase: The test case to execute
    ///   - executer: The executer to run commands on
    ///   - node: The node where the test runs
    ///   - testRunner: The test runner (simulator) to use
    ///   - runnerIndex: Index of the runner for logging
    ///   - previewHandler: Callback invoked when test result is available (before xcresult finalized)
    /// - Returns: The test case result, or nil if execution failed without producing a result
    func execute(
        testCase: TestCase,
        executer: Executer,
        node: Node,
        testRunner: TestRunner,
        runnerIndex: Int,
        previewHandler: @escaping PreviewHandler
    ) throws -> TestCaseResult? {
        var testCaseResult: TestCaseResult?

        try autoreleasepool {
            // Clean up previous test results
            try xcResultHandler.cleanupPreviousResults(executer: executer, testRunner: testRunner)

            // Execute the test
            let testExecuter = testExecuterBuilder(executer, testCase, node, testRunner, runnerIndex)
            var xcodebuildOutput = ""
            (xcodebuildOutput, testCaseResult) = try testExecuter.launch { previewResult in
                previewHandler(previewResult)
            }

            // Analyze output for failures
            try handleOutputAnalysis(xcodebuildOutput: xcodebuildOutput, executer: executer, testRunner: testRunner)

            // Handle xcresult
            testCaseResult = try handleXCResult(
                executer: executer,
                testRunner: testRunner,
                testCaseResult: testCaseResult
            )

            // Handle coverage
            let individualCoverageFile = try handleCoverage(
                executer: executer,
                testRunner: testRunner,
                testCaseResult: testCaseResult,
                node: node,
                runnerIndex: runnerIndex
            )

            // Schedule post-execution tasks
            schedulePostExecution(
                executer: executer,
                testRunner: testRunner,
                testCaseResult: testCaseResult,
                individualCoverageFile: individualCoverageFile
            )
        }

        return testCaseResult
    }

    // MARK: - Private

    private func handleOutputAnalysis(xcodebuildOutput: String, executer: Executer, testRunner: TestRunner) throws {
        let analysis = outputAnalyzer.analyze(xcodebuildOutput)

        if analysis.failedLoadingAccessibility {
            simulatorRecovery.forceReset(executer: executer, testRunner: testRunner)
        }

        try outputAnalyzer.assertAccessibilityPermissions(in: xcodebuildOutput)

        if analysis.requiresBootstrapWait {
            Thread.sleep(forTimeInterval: 10.0)
        }

        if analysis.failedPreflightChecks {
            simulatorRecovery.forceReset(executer: executer, testRunner: testRunner)
        }

        if analysis.damagedBuild {
            try simulatorRecovery.handleDamagedBuild(executer: executer)
        }
    }

    private func handleXCResult(
        executer: Executer,
        testRunner: TestRunner,
        testCaseResult: TestCaseResult?
    ) throws -> TestCaseResult? {
        guard var result = testCaseResult,
              let xcResultUrl = try xcResultHandler.findTestResultUrl(executer: executer, testRunner: testRunner) else {
            return testCaseResult
        }

        try xcResultHandler.reclaimDiskSpace(executer: executer, path: xcResultUrl.path)
        result.xcResultPath = try xcResultHandler.moveToResultsFolder(executer: executer, xcResultUrl: xcResultUrl, testRunner: testRunner)

        return result
    }

    private func handleCoverage(
        executer: Executer,
        testRunner: TestRunner,
        testCaseResult: TestCaseResult?,
        node: Node,
        runnerIndex: Int
    ) throws -> String? {
        let searchPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        let coverageFiles = try coverageHandler.findCoverageFiles(executer: executer, coveragePath: searchPath)

        // Find and save individual coverage if enabled
        var individualCoverageFile: String?
        if let testCaseResult = testCaseResult,
           testCaseResult.status == .passed,
           let newCoverageFile = coverageHandler.findNewCoverageFile(in: coverageFiles),
           configuration.testing.extractIndividualTestCoverage || configuration.testing.extractTestCoveredFiles {
            individualCoverageFile = coverageHandler.saveIndividualCoverage(
                executer: executer,
                testCaseResult: testCaseResult,
                newCoverageFile: newCoverageFile,
                searchPath: searchPath
            )
        }

        // Progressive merge
        coverageHandler.progressiveMerge(
            executer: executer,
            coverageFiles: coverageFiles,
            nodeAddress: node.address,
            runnerIndex: runnerIndex
        )

        return individualCoverageFile
    }

    private func schedulePostExecution(
        executer: Executer,
        testRunner: TestRunner,
        testCaseResult: TestCaseResult?,
        individualCoverageFile: String?
    ) {
        guard let groupExecuter = try? executer.clone() else { return }

        // A logger records strictly alternating start/end events and crashes on dump
        // if a second operation appends while one is in flight. So each concurrently
        // running post-execution operation needs its own logger object. To avoid two
        // loggers sharing a filename (which clobber each other on dump) we hand out
        // distinct, indexed names and recycle them via a checkout/checkin pool: file
        // count stays bounded to the actual concurrency instead of one per test case.
        let baseName = (executer.logger?.name ?? "") + "-async"
        let address = executer.logger?.address ?? ""
        let logger = checkoutAsyncLogger(baseName: baseName, address: address)
        groupExecuter.logger = logger

        postExecutionQueue.addOperation { [postExecutionHandler, weak self] in
            postExecutionHandler.process(
                executer: groupExecuter,
                testRunner: testRunner,
                testCaseResult: testCaseResult,
                individualCoverageFile: individualCoverageFile
            )
            self?.checkinAsyncLogger(logger, baseName: baseName)
        }
    }

    private func checkoutAsyncLogger(baseName: String, address: String) -> ExecuterLogger {
        asyncLoggersQueue.sync {
            if let reused = idleAsyncLoggers[baseName]?.popLast() {
                return reused
            }
            let index = asyncLoggerCounts[baseName, default: 0] + 1
            asyncLoggerCounts[baseName] = index
            let name = index == 1 ? baseName : "\(baseName)-\(index)"
            let logger = ExecuterLogger(name: name, address: address)
            addLogger(logger)
            return logger
        }
    }

    private func checkinAsyncLogger(_ logger: ExecuterLogger, baseName: String) {
        asyncLoggersQueue.sync {
            idleAsyncLoggers[baseName, default: []].append(logger)
        }
    }
}
