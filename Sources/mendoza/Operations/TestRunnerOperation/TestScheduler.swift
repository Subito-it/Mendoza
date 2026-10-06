//
//  TestScheduler.swift
//  Mendoza
//
//  Created by Tomas Camin on 06/10/26.
//

import Foundation

/// Decides what each runner does next. Runners are identified by their index in the list the
/// scheduler is created with, and every one of them must poll `nextState(for:)` until it returns
/// `.allRunnersCompleted`, or report `runnerExited(_:)`: a test case excluded from one runner
/// waits for the others, so a runner that never polls would hold it forever.
class TestScheduler {
    enum State: Equatable {
        case execute(TestCase)
        case waitingCompletion
        case quarantinedWaiting
        case recover
        case allRunnersCompleted
    }

    enum Requeue: Equatable {
        case relaunch(count: Int)
        case retry(count: Int)
    }

    private let syncQueue = DispatchQueue(label: String(describing: TestScheduler.self))
    private let testQueue: TestQueue
    private let runnerNodes: [Node]
    private let quarantineCooldown: TimeInterval
    private let now: () -> TimeInterval

    private var busyRunners = Set<Int>()
    /// A simulator that fails to launch the test runner (e.g. "Application failed preflight checks")
    /// is wedged at the host level and keeps failing every test routed to it, so it is taken out of
    /// rotation. After a cooldown it is fully cycled (shutdown -> boot) and rejoins. Value is the
    /// quarantine start time.
    private var quarantinedRunners = [Int: TimeInterval]()
    /// A runner whose test throws exits early while the others keep going, and it will never
    /// dequeue again: exclusions must not wait on it.
    private var exitedRunners = Set<Int>()

    var retryCount: Int {
        testQueue.retryCount
    }

    /// - Parameter runnerNodes: the node of each runner, by runner index
    init(testCases: [TestCase], runnerNodes: [Node], maxRetryCount: Int, quarantineCooldown: TimeInterval = 120, now: @escaping () -> TimeInterval = CFAbsoluteTimeGetCurrent) {
        self.testQueue = TestQueue(testCases: testCases, maxRetryCount: maxRetryCount)
        self.runnerNodes = runnerNodes
        self.quarantineCooldown = quarantineCooldown
        self.now = now
    }

    func nextState(for runnerIndex: Int) -> State {
        syncQueue.sync {
            // A quarantined runner is idle, so completion can only be declared once the queue is
            // also drained. Otherwise, if every runner were quarantined while tests remain, the
            // run would terminate and silently drop the pending tests.
            let queueEmpty = testQueue.count == 0
            if queueEmpty, busyRunners.isEmpty {
                return .allRunnersCompleted
            }

            if let quarantineStart = quarantinedRunners[runnerIndex] {
                return now() - quarantineStart >= quarantineCooldown ? .recover : .quarantinedWaiting
            }

            if let testCase = testQueue.dequeue(for: runnerIndex) {
                busyRunners.insert(runnerIndex)
                return .execute(testCase)
            }

            // Every queued test case is excluded on this runner. If no runner that could still
            // pick one up is available, nothing will ever dequeue them and every runner would wait
            // forever, so honor the exclusion only while such a runner exists.
            if !queueEmpty, !hasRunnerAvailableForQueuedTestCases(excluding: runnerIndex), let testCase = testQueue.dequeueIgnoringExclusions() {
                busyRunners.insert(runnerIndex)
                return .execute(testCase)
            }

            busyRunners.remove(runnerIndex)
            return .waitingCompletion
        }
    }

    /// Requeues a failed test case away from the runner that failed it.
    /// - Parameter didStartTest: false when the test method never started, in which case the runner
    ///   is to blame rather than the test: it is relaunched without charging its retry budget, and
    ///   only that runner is excluded since the failure says nothing about the others on its node
    /// - Returns: how the test case was requeued, or nil once its budget is exhausted
    func requeue(_ testCase: TestCase, didStartTest: Bool, runnerIndex: Int) -> Requeue? {
        syncQueue.sync {
            if !didStartTest, testQueue.enqueueForRelaunch(testCase, excludedRunnerIndexes: [runnerIndex]) {
                return .relaunch(count: testQueue.relaunchCount(for: testCase))
            }

            if testQueue.enqueueForRetry(testCase, excludedRunnerIndexes: runnerIndexes(onNodeOf: runnerIndex)) {
                return .retry(count: testQueue.retryCount(for: testCase))
            }

            return nil
        }
    }

    func beginQuarantine(_ runnerIndex: Int) {
        syncQueue.sync {
            quarantinedRunners[runnerIndex] = now()
            busyRunners.remove(runnerIndex)
        }
    }

    func endQuarantine(_ runnerIndex: Int) {
        syncQueue.sync {
            quarantinedRunners[runnerIndex] = nil
        }
    }

    func runnerExited(_ runnerIndex: Int) {
        syncQueue.sync {
            busyRunners.remove(runnerIndex)
            exitedRunners.insert(runnerIndex)
        }
    }

    /// Must be called on `syncQueue`. `TestQueue` has its own lock, so querying it here is safe.
    private func hasRunnerAvailableForQueuedTestCases(excluding runnerIndex: Int) -> Bool {
        // Busy and quarantined runners count as available: both return for more work later. Runners
        // that exited do not.
        let otherRunnerIndexes = runnerNodes.indices.filter { $0 != runnerIndex && !exitedRunners.contains($0) }
        return testQueue.containsTestCase(eligibleForAnyOf: otherRunnerIndexes)
    }

    private func runnerIndexes(onNodeOf runnerIndex: Int) -> Set<Int> {
        guard runnerNodes.indices.contains(runnerIndex) else { return [runnerIndex] }
        return Set(runnerNodes.indices.filter { runnerNodes[$0] == runnerNodes[runnerIndex] })
    }
}
