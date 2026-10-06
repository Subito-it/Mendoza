//
//  TestRunnerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestRunnerOperation: BaseOperation<[TestCaseResult]> {
    var sortedTestCases: [TestCase]?
    var testRunners: [(testRunner: TestRunner, node: Node)]?

    private let configuration: Configuration

    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private var testCasesCount = 0
    private var testCasesCompletedCount = 0

    private let resultHandler: TestResultHandler
    private let testCaseExecutor: TestCaseExecutor
    private let simulatorRecovery: SimulatorRecovery
    private let diagnosticReporter: DiagnosticReporter

    /// Bounded so the per-test result transfers don't open an unbounded burst of
    /// SSH connections to the single result destination, which can exceed its sshd
    /// MaxStartups limit and cause transfers to be silently dropped.
    private let postExecutionQueue = ThreadQueue(maxConcurrentOperations: 8)

    private lazy var pool: ConnectionPool<(index: Int, testRunner: TestRunner)> = {
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }

        // Each source carries the index of its runner in `testRunners`, which is how the scheduler
        // identifies runners. Matching on (id, name) instead is not safe: simulator names repeat per
        // node, and a wedged simulator can have an empty id.
        //
        // Every runner gets a worker, even with fewer tests than runners: the scheduler expects
        // every runner it knows of to poll it.
        return makeConnectionPool(sources: testRunners.enumerated().map { offset, runner in
            (node: runner.node, value: (index: offset, testRunner: runner.testRunner))
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

            let scheduler = TestScheduler(testCases: sortedTestCases ?? [],
                                          runnerNodes: testRunners?.map(\.node) ?? [],
                                          maxRetryCount: configuration.testing.failingTestsRetryCount ?? 0)

            try pool.execute(block: { [weak self] executer, source in
                guard let self = self else { return }

                let runnerIndex = source.value.index
                let testRunner = source.value.testRunner

                while true {
                    switch scheduler.nextState(for: runnerIndex) {
                    case .allRunnersCompleted:
                        return
                    case .waitingCompletion, .quarantinedWaiting:
                        Thread.sleep(forTimeInterval: 1.0)
                        continue
                    case .recover:
                        self.simulatorRecovery.boot(executer: executer, testRunner: testRunner)
                        scheduler.endQuarantine(runnerIndex)
                        print("🚧 Recovered runner \(testRunner.name) on \(source.node.address), resuming test execution {\(runnerIndex)}".green)
                        continue
                    case let .execute(testCase):
                        let outcome = try self.testCaseExecutor.execute(
                            testCase: testCase,
                            executer: executer,
                            node: source.node,
                            testRunner: testRunner,
                            runnerIndex: runnerIndex,
                            previewHandler: { [weak self] previewResult, didStartTest in
                                self?.handleTestCaseResultPreview(previewResult, didStartTest: didStartTest, testCase: testCase, runnerIndex: runnerIndex, scheduler: scheduler)
                            }
                        )

                        if let result = outcome.result {
                            self.syncQueue.sync { results.append(result) }
                        }

                        if outcome.requiresQuarantine {
                            // Take the wedged simulator out of rotation and shut it down. The boot is
                            // deferred to the recovery step after the cooldown, by which point the
                            // shutdown has completed.
                            self.simulatorRecovery.forceReset(executer: executer, testRunner: testRunner)
                            scheduler.beginQuarantine(runnerIndex)
                            print("🚧 Quarantined runner \(testRunner.name) on \(source.node.address) after simulator launch failure {\(runnerIndex)}".yellow)
                        }
                    }
                }

                try self.diagnosticReporter.copyDiagnosticReports(executer: executer, testRunner: testRunner)
            }, sourceDidExit: { source in
                // Also reached when the runner's connection fails, before any of the above runs: the
                // scheduler would otherwise keep waiting for a runner that will never poll it.
                scheduler.runnerExited(source.value.index)
            })

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

    private func handleTestCaseResultPreview(_ previewResult: TestCaseResult, didStartTest: Bool, testCase: TestCase, runnerIndex: Int, scheduler: TestScheduler) {
        syncQueue.sync {
            testCasesCompletedCount += 1

            resultHandler.printStatus(
                previewResult,
                testCase: testCase,
                completedCount: testCasesCompletedCount,
                totalCount: testCasesCount,
                retryCount: scheduler.retryCount,
                runnerIndex: runnerIndex
            )

            guard previewResult.status == .failed else { return }

            switch scheduler.requeue(testCase, didStartTest: didStartTest, runnerIndex: runnerIndex) {
            case let .relaunch(count):
                testCasesCount += 1
                resultHandler.printRelaunchEnqueue(testCase, relaunchCount: count)
            case let .retry(count):
                testCasesCount += 1
                resultHandler.printRetryEnqueue(testCase, retryCount: count)
            case nil:
                break
            }
        }
    }
}
