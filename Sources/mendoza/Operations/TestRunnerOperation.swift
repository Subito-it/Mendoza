//
//  TestRunnerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestRunnerOperation: BaseOperation<[TestCaseResult]> {
    var sortedTestCases: [TestCase]?
    var testRunners: [(testRunner: TestRunner, node: Node, idle: Bool)]?

    private let configuration: Configuration

    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private var testCasesCount = 0
    private var testCasesCompletedCount = 0

    private lazy var testQueue: TestQueue = .init(
        testCases: sortedTestCases ?? [],
        maxRetryCount: configuration.testing.failingTestsRetryCount ?? 0
    )

    private let resultHandler: TestResultHandler
    private let testCaseExecutor: TestCaseExecutor
    private let diagnosticReporter: DiagnosticReporter
    private let postExecutionQueue = ThreadQueue()

    private lazy var pool: ConnectionPool<TestRunner> = {
        guard let sortedTestCases = sortedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }

        let input = zip(testRunners, sortedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: $0.0.testRunner) })
    }()

    init(configuration: Configuration, baseUrl: URL, destinationPath: String, testTarget: String, productNames: [String]) {
        self.configuration = configuration

        let testExecuterBuilder: TestCaseExecutor.TestExecuterBuilder = { executer, testCase, node, testRunner, runnerIndex in
            TestExecuter(
                executer: executer,
                testCase: testCase,
                testTarget: testTarget,
                building: configuration.building,
                testing: configuration.testing,
                node: node,
                testRunner: testRunner,
                runnerIndex: runnerIndex,
                verbose: configuration.verbose
            )
        }

        self.resultHandler = TestResultHandler(verbose: configuration.verbose)

        let xcResultHandler = XCResultHandler(xcresultBlobThresholdKB: configuration.testing.xcresultBlobThresholdKB)
        let outputAnalyzer = OutputAnalyzer()
        let coverageHandler = CoverageHandler(verbose: configuration.verbose)
        let simulatorRecovery = SimulatorRecovery(verbose: configuration.verbose)
        self.diagnosticReporter = DiagnosticReporter(productNames: productNames)
        let postExecutionHandler = PostExecutionHandler(
            configuration: configuration,
            baseUrl: baseUrl,
            destinationPath: destinationPath
        )

        // Temporary placeholder for addLogger - will be set after super.init
        var addLoggerClosure: ((ExecuterLogger) -> Void)?

        self.testCaseExecutor = TestCaseExecutor(
            configuration: configuration,
            testExecuterBuilder: testExecuterBuilder,
            xcResultHandler: xcResultHandler,
            outputAnalyzer: outputAnalyzer,
            coverageHandler: coverageHandler,
            simulatorRecovery: simulatorRecovery,
            postExecutionHandler: postExecutionHandler,
            postExecutionQueue: postExecutionQueue,
            addLogger: { logger in addLoggerClosure?(logger) }
        )

        super.init()

        addLoggerClosure = { [weak self] logger in
            self?.addLogger(logger)
        }
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            var results = [TestCaseResult]()

            testCasesCount = sortedTestCases?.count ?? 0
            guard testCasesCount > 0 else {
                didEnd?(results)
                return
            }

            try pool.execute { [weak self] executer, source in
                guard let self = self else { return }

                let testRunner = source.value
                let runnerIndex = self.runnerIndex(for: testRunner)

                defer { self.syncQueue.sync { self.testRunners?[runnerIndex].idle = true } }

                while true {
                    let state = self.determineRunnerState(testRunner: testRunner, source: source)

                    switch state {
                    case .allRunnersCompleted:
                        return
                    case .waitingCompletion:
                        Thread.sleep(forTimeInterval: 1.0)
                        continue
                    case let .execute(testCase):
                        let testCaseResult = try self.testCaseExecutor.execute(
                            testCase: testCase,
                            executer: executer,
                            node: source.node,
                            testRunner: testRunner,
                            runnerIndex: runnerIndex,
                            previewHandler: { [weak self] previewResult in
                                self?.handleTestCaseResultPreview(previewResult, testCase: testCase, runnerIndex: runnerIndex)
                            }
                        )

                        if let result = testCaseResult {
                            self.syncQueue.sync { results.append(result) }
                        }
                    }
                }

                try self.diagnosticReporter.copyDiagnosticReports(executer: executer, testRunner: testRunner)
            }

            postExecutionQueue.waitUntilAllOperationsAreFinished()

            didEnd?(results)
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

    // MARK: - Private

    private enum State {
        case execute(TestCase)
        case waitingCompletion
        case allRunnersCompleted
    }

    private func determineRunnerState(testRunner: TestRunner, source: ConnectionPool<TestRunner>.Source<TestRunner>) -> State {
        syncQueue.sync {
            if let testCase = testQueue.dequeue() {
                updateRunnerIdleState(testRunner: testRunner, source: source, idle: false)
                return .execute(testCase)
            }

            updateRunnerIdleState(testRunner: testRunner, source: source, idle: true)

            let allRunnersCompleted = testRunners?.allSatisfy(\.idle) == true
            return allRunnersCompleted ? .allRunnersCompleted : .waitingCompletion
        }
    }

    private func updateRunnerIdleState(testRunner: TestRunner, source: ConnectionPool<TestRunner>.Source<TestRunner>, idle: Bool) {
        if let index = testRunners?.firstIndex(where: { $0.node == source.node && $0.testRunner.id == testRunner.id && $0.testRunner.name == testRunner.name }) {
            testRunners?[index].idle = idle
        }
    }

    private func handleTestCaseResultPreview(_ previewResult: TestCaseResult, testCase: TestCase, runnerIndex: Int) {
        syncQueue.sync {
            testCasesCompletedCount += 1

            resultHandler.printStatus(
                previewResult,
                testCase: testCase,
                completedCount: testCasesCompletedCount,
                totalCount: testCasesCount,
                retryCount: testQueue.retryCount,
                runnerIndex: runnerIndex
            )

            if previewResult.status == .failed {
                if testQueue.enqueueForRetry(testCase) {
                    testCasesCount += 1
                    resultHandler.printRetryEnqueue(testCase, retryCount: testQueue.retryCount(for: testCase))
                }
            }
        }
    }

    private func runnerIndex(for testRunner: TestRunner) -> Int {
        syncQueue.sync { [unowned self] in
            testRunners?.firstIndex { $0.0.id == testRunner.id && $0.0.name == testRunner.name } ?? 0
        }
    }
}
