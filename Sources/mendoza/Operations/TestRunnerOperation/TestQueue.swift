//
//  TestQueue.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Thread-safe work-stealing queue for test case distribution with retry support
class TestQueue {
    private let syncQueue = DispatchQueue(label: String(describing: TestQueue.self))
    private var testCases: [TestCase]
    private var retryCountMap = NSCountedSet()
    private let maxRetryCount: Int
    /// Runner indexes a test case must not be dequeued by, so a retry lands on a different node.
    private var excludedRunners = [TestCase: Set<Int>]()
    private var singletonTests = Set<TestCase>()

    /// One reservation holds the queue lock for all members. Retries and returned work stay singletons.
    func dequeueBatch(for runnerIndex: Int, maximumCount: Int, ignoringExclusions: Bool = false) -> [TestCase] {
        syncQueue.sync {
            let eligible: (TestCase) -> Bool = { ignoringExclusions || self.excludedRunners[$0]?.contains(runnerIndex) != true }
            guard let firstIndex = testCases.firstIndex(where: eligible) else { return [] }
            let first = testCases.remove(at: firstIndex)
            guard maximumCount > 1, retryCountMap.count(for: first) == 0, !singletonTests.contains(first) else { return [first] }
            var batch = [first]
            while batch.count < maximumCount,
                  let index = testCases.firstIndex(where: { eligible($0) && retryCountMap.count(for: $0) == 0 && !singletonTests.contains($0) }) {
                batch.append(testCases.remove(at: index))
            }
            return batch
        }
    }

    /// These tests never started, so this is not a failed attempt and consumes no retry budget.
    func returnUnstarted(_ tests: [TestCase]) {
        syncQueue.sync {
            singletonTests.formUnion(tests)
            testCases.insert(contentsOf: tests, at: 0)
        }
    }

    var count: Int {
        syncQueue.sync { testCases.count }
    }

    var retryCount: Int {
        syncQueue.sync {
            retryCountMap.reduce(0) { $0 + retryCountMap.count(for: $1) }
        }
    }

    init(testCases: [TestCase], maxRetryCount: Int) {
        self.testCases = testCases
        self.maxRetryCount = maxRetryCount
    }

    /// Atomically dequeue the next test case the given runner is allowed to execute, skipping
    /// test cases that previously failed on its node.
    /// - Returns: The next eligible test case, or nil if none is available
    func dequeue(for runnerIndex: Int) -> TestCase? {
        syncQueue.sync {
            guard let index = testCases.firstIndex(where: { excludedRunners[$0]?.contains(runnerIndex) != true }) else {
                return nil
            }
            return testCases.remove(at: index)
        }
    }

    /// Atomically dequeue the next test case ignoring retry exclusions. Only meant for the case
    /// where no other runner can pick up the remaining test cases, which would otherwise stall the run.
    func dequeueIgnoringExclusions() -> TestCase? {
        syncQueue.sync {
            testCases.isEmpty ? nil : testCases.removeFirst()
        }
    }

    /// Whether any queued test case can be dequeued by at least one of the given runners
    func containsTestCase(eligibleForAnyOf runnerIndexes: [Int]) -> Bool {
        syncQueue.sync {
            testCases.contains { testCase in
                let excluded = excludedRunners[testCase] ?? []
                return runnerIndexes.contains { !excluded.contains($0) }
            }
        }
    }

    /// Enqueue a test case for retry after failure
    /// - Parameters:
    ///   - testCase: The test case to retry
    ///   - excludedRunnerIndexes: Runners that should not pick the test case up again, typically
    ///     all runners on the node that just failed it
    /// - Returns: true if the test was enqueued for retry, false if max retries exceeded
    func enqueueForRetry(_ testCase: TestCase, excludedRunnerIndexes: Set<Int>) -> Bool {
        syncQueue.sync {
            let currentRetryCount = retryCountMap.count(for: testCase)
            guard currentRetryCount < maxRetryCount else {
                return false
            }

            retryCountMap.add(testCase)
            excludedRunners[testCase, default: []].formUnion(excludedRunnerIndexes)
            testCases.insert(testCase, at: 0)

            return true
        }
    }

    /// Get the current retry count for a specific test case
    func retryCount(for testCase: TestCase) -> Int {
        syncQueue.sync {
            retryCountMap.count(for: testCase)
        }
    }
}
