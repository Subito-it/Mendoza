@testable import mendoza
import XCTest

final class TestSchedulerTests: XCTestCase {
    private enum Outcome {
        case passed
        case failed
        case neverStarted
    }

    private let testCase = TestCase(name: "testLogin", suite: "LoginTests")
    private let nodeA = Node(name: "a", address: "a.local", authentication: nil, concurrentTestRunners: .autodetect)
    private let nodeB = Node(name: "b", address: "b.local", authentication: nil, concurrentTestRunners: .autodetect)

    func testTestThatNeverStartedIsRelaunchedOnAnotherRunner() throws {
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA, nodeA], maxRetryCount: 0)

        let runs = try XCTUnwrap(drive(scheduler, runners: [0, 1]) { _, runner in runner == 0 ? .neverStarted : .passed })

        XCTAssertEqual(runs.map(\.runner), [0, 1])
    }

    func testRetryRunsOnAnotherNode() throws {
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA, nodeA, nodeB, nodeB], maxRetryCount: 1)

        let runs = try XCTUnwrap(drive(scheduler, runners: [0, 1, 2, 3]) { attempt, _ in attempt == 0 ? .failed : .passed })

        XCTAssertEqual(runs.count, 2)
        XCTAssertTrue([2, 3].contains(runs[1].runner), "retried on runner \(runs[1].runner), on the node that failed it")
    }

    func testRetryRunsOnTheSameNodeWhenNoOtherExists() throws {
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA, nodeA], maxRetryCount: 1)

        let runs = try XCTUnwrap(drive(scheduler, runners: [0, 1]) { _, _ in .failed })

        XCTAssertEqual(runs.count, 2)
    }

    func testTestThatCannotStartAnywhereEnds() throws {
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA, nodeA], maxRetryCount: 1)

        let runs = try XCTUnwrap(drive(scheduler, runners: [0, 1]) { _, _ in .neverStarted })

        XCTAssertEqual(runs.count, 1 + TestQueue.maxRelaunchCount + 1)
    }

    func testExitedRunnerDoesNotHoldTestCasesExcludedFromOthers() throws {
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA, nodeA], maxRetryCount: 0)
        scheduler.runnerExited(1)

        let runs = try XCTUnwrap(drive(scheduler, runners: [0]) { attempt, _ in attempt == 0 ? .neverStarted : .passed })

        XCTAssertEqual(runs.map(\.runner), [0, 0])
    }

    /// The contract the operation must honor by starting a worker for every runner.
    func testRunnerThatNeverPollsHoldsTestCasesExcludedFromOthers() {
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA, nodeA], maxRetryCount: 0)

        XCTAssertNil(drive(scheduler, runners: [0]) { _, _ in .neverStarted })
    }

    func testQuarantinedRunnerRecoversAfterCooldown() {
        var time: TimeInterval = 0
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA], maxRetryCount: 0, quarantineCooldown: 120, now: { time })

        scheduler.beginQuarantine(0)
        XCTAssertEqual(scheduler.nextState(for: 0), .quarantinedWaiting, "pending tests must not let the run complete")

        time = 120
        XCTAssertEqual(scheduler.nextState(for: 0), .recover)

        scheduler.endQuarantine(0)
        XCTAssertEqual(scheduler.nextState(for: 0), .execute(testCase))
    }

    /// Polls the runners in turn, as the operation's workers do, executing every dequeued test case
    /// with the given outcome until each runner is told the run completed.
    /// - Parameters:
    ///   - runners: the runners that poll
    ///   - outcome: the result of a test case's nth execution on a runner
    /// - Returns: the runner of each execution in order, or nil if the run did not complete
    private func drive(_ scheduler: TestScheduler, runners: [Int], outcome: (_ attempt: Int, _ runner: Int) -> Outcome) -> [(testCase: TestCase, runner: Int)]? {
        var runs = [(testCase: TestCase, runner: Int)]()
        var pending = Set(runners)

        for _ in 0 ..< 100 {
            for runner in runners where pending.contains(runner) {
                switch scheduler.nextState(for: runner) {
                case let .execute(testCase):
                    let result = outcome(runs.filter { $0.testCase == testCase }.count, runner)
                    runs.append((testCase, runner))
                    if result != .passed {
                        _ = scheduler.requeue(testCase, didStartTest: result == .failed, runnerIndex: runner)
                    }
                case .allRunnersCompleted:
                    pending.remove(runner)
                    scheduler.runnerExited(runner)
                case .waitingCompletion, .quarantinedWaiting, .recover:
                    break
                }
            }

            if pending.isEmpty { return runs }
        }

        return nil
    }
}
