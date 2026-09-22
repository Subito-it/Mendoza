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
    private let testExecuter: TestExecuter
    private let simulatorRecovery: SimulatorRecovery
    private let diagnosticReporter: DiagnosticReporter

    /// A simulator that fails to launch the test runner (e.g. "Application failed preflight checks")
    /// is wedged at the host level and keeps failing every test routed to it. When that happens we
    /// quarantine the runner: shut its simulator down and stop pulling tests onto it. After a cooldown
    /// it is fully cycled (shutdown -> boot) and rejoins. Keyed by the runner's stable index in
    /// `testRunners` rather than testRunner.id, which is not guaranteed unique (an empty or
    /// duplicate id would let two runners alias the same dictionary entry). Value is the quarantine
    /// start time (CFAbsoluteTime).
    private var quarantinedRunners = [Int: TimeInterval]()
    /// Runners that left the execution loop, by index in `testRunners`. A runner whose test throws
    /// exits early while the others keep going, and it will never dequeue again: retry exclusions
    /// must not wait on it.
    private var exitedRunners = Set<Int>()
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

        self.resultHandler = TestResultHandler(verbose: configuration.verbose)
        self.simulatorRecovery = SimulatorRecovery(verbose: configuration.verbose)
        self.diagnosticReporter = DiagnosticReporter(productNames: productNames)

        // Temporary placeholder for addLogger - will be set after super.init
        var addLoggerClosure: ((ExecuterLogger) -> Void)?

        self.testExecuter = TestExecuter(configuration: configuration, target: testTarget, baseUrl: baseUrl, destinationPath: destinationPath, jobs: postExecutionQueue, addLogger: { logger in addLoggerClosure?(logger) })

        super.init()

        addLoggerClosure = { [weak self] logger in
            self?.addLogger(logger)
        }
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            try configuration.testing.validateBatchSize()
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

                defer {
                    self.syncQueue.sync {
                        self.testRunners?[runnerIndex].idle = true
                        self.exitedRunners.insert(runnerIndex)
                    }
                }

                while true {
                    if self.isCancelled {
                        return
                    }
                    let state = self.determineRunnerState(runnerIndex: runnerIndex, testRunner: testRunner)

                    switch state {
                    case .allRunnersCompleted:
                        try self.diagnosticReporter.copyDiagnosticReports(executer: executer, testRunner: testRunner)
                        return
                    case .waitingCompletion, .quarantinedWaiting:
                        Thread.sleep(forTimeInterval: 1.0)
                        continue
                    case .recover:
                        self.simulatorRecovery.boot(executer: executer, testRunner: testRunner)
                        self.endQuarantine(for: testRunner, runnerIndex: runnerIndex, node: source.node)
                        continue
                    case let .execute(tests):
                        let outcome = try self.testExecuter.execute(tests: tests, executer: executer, node: source.node, runner: testRunner) { [weak self] result, test in
                            self?.handleTestCaseResultPreview(result, testCase: test, runnerIndex: runnerIndex)
                        }
                        self.syncQueue.sync {
                            results.append(contentsOf: outcome.results)
                            self.testQueue.returnUnstarted(outcome.unstarted)
                        }
                        if outcome.requiresQuarantine {
                            self.beginQuarantine(for: testRunner, runnerIndex: runnerIndex, node: source.node, executer: executer)
                        }
                    }
                }
            }

            try testExecuter.finish()
            guard !isCancelled else { return }
            didEnd?(results)
        } catch {
            testExecuter.cancel()
            try? testExecuter.finish()
            didThrow?(error)
        }
    }

    override func cancel() {
        // Stop dequeuing before waiting for control connections to deliver cancellation markers.
        super.cancel()
        if isExecuting {
            testExecuter.cancel()
        }
    }

    // MARK: - Private

    private enum State {
        case execute([TestCase])
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

            var tests = testQueue.dequeueBatch(for: runnerIndex, maximumCount: configuration.testing.effectiveTestBatchSize)
            if tests.isEmpty, !queueEmpty, !hasRunnerAvailableForQueuedTestCases(excluding: runnerIndex) {
                tests = testQueue.dequeueBatch(for: runnerIndex, maximumCount: configuration.testing.effectiveTestBatchSize, ignoringExclusions: true)
            }
            testRunners?[runnerIndex].idle = tests.isEmpty
            return tests.isEmpty ? .waitingCompletion : .execute(tests)
        }
    }

    /// Must be called while holding `syncQueue`. `TestQueue` has its own lock, so querying it here is safe.
    private func hasRunnerAvailableForQueuedTestCases(excluding runnerIndex: Int) -> Bool {
        // Busy and quarantined runners count as available: both return for more work later. Runners
        // that left the loop do not.
        let otherRunnerIndexes = (testRunners?.indices ?? (0 ..< 0)).filter { $0 != runnerIndex && !exitedRunners.contains($0) }
        return testQueue.containsTestCase(eligibleForAnyOf: Array(otherRunnerIndexes))
    }

    private func runnerIndexes(onNodeOf runnerIndex: Int) -> Set<Int> {
        guard let testRunners = testRunners, testRunners.indices.contains(runnerIndex) else { return [runnerIndex] }
        let node = testRunners[runnerIndex].node
        return Set(testRunners.indices.filter { testRunners[$0].node == node })
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
                if testQueue.enqueueForRetry(testCase, excludedRunnerIndexes: runnerIndexes(onNodeOf: runnerIndex)) {
                    testCasesCount += 1
                    resultHandler.printRetryEnqueue(testCase, retryCount: testQueue.retryCount(for: testCase))
                }
            }
        }
    }
}
