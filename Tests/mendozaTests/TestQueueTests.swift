@testable import mendoza
import XCTest

final class TestQueueTests: XCTestCase {
    private let testCase = TestCase(name: "testLogin", suite: "LoginTests")

    func testRelaunchDoesNotChargeRetryBudget() {
        let queue = TestQueue(testCases: [], maxRetryCount: 1)

        XCTAssertTrue(queue.enqueueForRelaunch(testCase, excludedRunnerIndexes: [0]))
        XCTAssertEqual(queue.retryCount(for: testCase), 0)
        XCTAssertTrue(queue.enqueueForRetry(testCase, excludedRunnerIndexes: [1]))
    }

    func testRelaunchIsBounded() {
        let queue = TestQueue(testCases: [], maxRetryCount: 0)

        for _ in 0 ..< TestQueue.maxRelaunchCount {
            XCTAssertTrue(queue.enqueueForRelaunch(testCase, excludedRunnerIndexes: []))
        }

        XCTAssertFalse(queue.enqueueForRelaunch(testCase, excludedRunnerIndexes: []))
        XCTAssertEqual(queue.relaunchCount(for: testCase), TestQueue.maxRelaunchCount)
    }

    func testRelaunchExcludesFailingRunner() {
        let queue = TestQueue(testCases: [], maxRetryCount: 0)

        XCTAssertTrue(queue.enqueueForRelaunch(testCase, excludedRunnerIndexes: [3]))

        XCTAssertNil(queue.dequeue(for: 3))
        XCTAssertEqual(queue.dequeue(for: 4), testCase)
    }
}
