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

    /// Atomically dequeue the next test case
    /// - Returns: The next test case, or nil if queue is empty
    func dequeue() -> TestCase? {
        syncQueue.sync {
            guard let testCase = testCases.first else {
                return nil
            }
            testCases.removeFirst()
            return testCase
        }
    }

    /// Enqueue a test case for retry after failure
    /// - Parameter testCase: The test case to retry
    /// - Returns: true if the test was enqueued for retry, false if max retries exceeded
    func enqueueForRetry(_ testCase: TestCase) -> Bool {
        syncQueue.sync {
            let currentRetryCount = retryCountMap.count(for: testCase)
            guard currentRetryCount < maxRetryCount else {
                return false
            }

            retryCountMap.add(testCase)

            // Insert at index 1 (if possible) so the test runs on a different simulator
            if testCases.isEmpty {
                testCases.append(testCase)
            } else {
                testCases.insert(testCase, at: 1)
            }

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
