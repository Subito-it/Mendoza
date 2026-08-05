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
    private let simulatorRecovery: SimulatorRecovery
    private let diagnosticReporter: DiagnosticReporter

    // A simulator that fails to launch the test runner (e.g. "Application failed preflight checks")
    // is wedged at the host level and keeps failing every test routed to it. When that happens we
    // quarantine the runner: shut its simulator down and stop pulling tests onto it. After a cooldown
    // it is fully cycled (shutdown -> boot) and rejoins. Keyed by the runner's stable index in
    // `testRunners` rather than testRunner.id, which is not guaranteed unique (an empty or
    // duplicate id would let two runners alias the same dictionary entry). Value is the quarantine
    // start time (CFAbsoluteTime).
    private var quarantinedRunners = [Int: TimeInterval]()
    private let quarantineCooldown: TimeInterval = 120
    /// Bounded so the per-test result transfers don't open an unbounded burst of
    /// SSH connections to the single result destination, which can exceed its sshd
    /// MaxStartups limit and cause transfers to be silently dropped.
    private let postExecutionQueue = ThreadQueue(maxConcurrentOperations: 8)

    private lazy var pool: ConnectionPool<(index: Int, testRunner: TestRunner)> = {
        guard let sortedTestCases = sortedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }

        // Each source carries the index of its runner in `testRunners`, assigned once here. Every
        // read/write of the runner's `idle` flag keys off this index instead of matching on
        // (id, name), which is not guaranteed unique across nodes (simulator names repeat per node,
        // and a wedged simulator can have an empty id). A mismatched lookup would leave a runner
        // stuck at idle=false forever, so the `allRunnersIdle` completion barrier could never
        // release and every runner thread would spin in `.waitingCompletion`.
        let input = zip(testRunners, sortedTestCases).enumerated()
        return makeConnectionPool(sources: input.map { offset, pair in
            (node: pair.0.node, value: (index: offset, testRunner: pair.0.testRunner))
        })
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
        self.simulatorRecovery = simulatorRecovery
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

                let runnerIndex = source.value.index
                let testRunner = source.value.testRunner

                defer { self.syncQueue.sync { self.testRunners?[runnerIndex].idle = true } }

                while true {
                    let state = self.determineRunnerState(runnerIndex: runnerIndex, testRunner: testRunner)

                    switch state {
                    case .allRunnersCompleted:
                        return
                    case .waitingCompletion, .quarantinedWaiting:
                        Thread.sleep(forTimeInterval: 1.0)
                        continue
                    case .recover:
                        self.simulatorRecovery.boot(executer: executer, testRunner: testRunner)
                        self.endQuarantine(for: testRunner, runnerIndex: runnerIndex, node: source.node)
                        continue
                    case let .execute(testCase):
                        let outcome = try self.testCaseExecutor.execute(
                            testCase: testCase,
                            executer: executer,
                            node: source.node,
                            testRunner: testRunner,
                            runnerIndex: runnerIndex,
                            previewHandler: { [weak self] previewResult in
                                self?.handleTestCaseResultPreview(previewResult, testCase: testCase, runnerIndex: runnerIndex)
                            }
                        )

                        if let result = outcome.result {
                            self.syncQueue.sync { results.append(result) }
                        }

                        if outcome.requiresQuarantine {
                            self.beginQuarantine(for: testRunner, runnerIndex: runnerIndex, node: source.node, executer: executer)
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
        case quarantinedWaiting
        case recover
        case allRunnersCompleted
    }

    private func determineRunnerState(runnerIndex: Int, testRunner: TestRunner) -> State {
        syncQueue.sync {
            // A quarantined runner is idle, so completion can only be declared once the queue is
            // also drained. Otherwise, if every runner were quarantined while tests remain, the
            // run would terminate and silently drop the pending tests.
            let queueEmpty = testQueue.count == 0
            let allRunnersIdle = testRunners?.allSatisfy(\.idle) == true
            if queueEmpty, allRunnersIdle {
                return .allRunnersCompleted
            }

            if let quarantineStart = quarantinedRunners[runnerIndex] {
                let elapsed = CFAbsoluteTimeGetCurrent() - quarantineStart
                return elapsed >= quarantineCooldown ? .recover : .quarantinedWaiting
            }

            if let testCase = testQueue.dequeue() {
                testRunners?[runnerIndex].idle = false
                return .execute(testCase)
            }

            testRunners?[runnerIndex].idle = true
            return .waitingCompletion
        }
    }

    private func beginQuarantine(for testRunner: TestRunner, runnerIndex: Int, node: Node, executer: Executer) {
        // Take the wedged simulator out of rotation and shut it down. The boot is deferred to the
        // recovery step after the cooldown, by which point the shutdown has completed.
        simulatorRecovery.forceReset(executer: executer, testRunner: testRunner)

        syncQueue.sync {
            quarantinedRunners[runnerIndex] = CFAbsoluteTimeGetCurrent()
            testRunners?[runnerIndex].idle = true
        }

        print("🚧 Quarantined runner \(testRunner.name) on \(node.address) after simulator launch failure {\(runnerIndex)}".yellow)
    }

    private func endQuarantine(for testRunner: TestRunner, runnerIndex: Int, node: Node) {
        syncQueue.sync {
            quarantinedRunners[runnerIndex] = nil
        }

        print("🚧 Recovered runner \(testRunner.name) on \(node.address), resuming test execution {\(runnerIndex)}".green)
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
}
