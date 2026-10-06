@testable import mendoza
import XCTest

final class ConnectionPoolTests: XCTestCase {
    private let nodeA = Node(name: "a", address: "a.local", authentication: nil, concurrentTestRunners: .autodetect)
    private let testCase = TestCase(name: "testLogin", suite: "LoginTests")

    func testSourceExitsWhenItsConnectionFails() {
        let pool = makePool(runnerCount: 2, failingConnections: [1])
        let exited = Locked<[Int]>([])
        let executed = Locked<[Int]>([])

        XCTAssertThrowsError(try pool.execute(block: { _, source in executed.mutate { $0.append(source.value) } },
                                              sourceDidExit: { source in exited.mutate { $0.append(source.value) } }))

        XCTAssertEqual(executed.value, [0])
        XCTAssertEqual(exited.value.sorted(), [0, 1])
    }

    /// A runner whose connection fails never polls the scheduler, so it must still be reported as
    /// exited: otherwise a test excluded from the remaining runner waits for it forever.
    func testRunnerWhoseConnectionFailsDoesNotHoldExcludedTestCases() {
        let pool = makePool(runnerCount: 2, failingConnections: [1])
        let scheduler = TestScheduler(testCases: [testCase], runnerNodes: [nodeA, nodeA], maxRetryCount: 0)
        let runs = Locked<[Int]>([])
        let finished = expectation(description: "pool finished")

        DispatchQueue.global().async {
            _ = try? pool.execute(block: { _, source in
                while true {
                    switch scheduler.nextState(for: source.value) {
                    case let .execute(testCase):
                        let attempt = runs.mutate { $0.append(source.value); return $0.count - 1 }
                        if attempt == 0 {
                            _ = scheduler.requeue(testCase, didStartTest: false, runnerIndex: source.value)
                        }
                    case .allRunnersCompleted:
                        return
                    case .waitingCompletion, .quarantinedWaiting, .recover:
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }, sourceDidExit: { source in scheduler.runnerExited(source.value) })
            finished.fulfill()
        }

        wait(for: [finished], timeout: 10)
        XCTAssertEqual(runs.value, [0, 0])
    }

    private func makePool(runnerCount: Int, failingConnections: Set<Int>) -> ConnectionPool<Int> {
        let sources = (0 ..< runnerCount).map { ConnectionPool<Int>.Source(node: nodeA, value: $0, environment: [:], logger: nil) }
        return ConnectionPool(sources: sources) { source in
            guard !failingConnections.contains(source.value) else { throw Error("Connection to runner \(source.value) failed") }
            return LocalExecuter()
        }
    }
}

private final class Locked<Value> {
    private let queue = DispatchQueue(label: "Locked")
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        queue.sync { storage }
    }

    @discardableResult
    func mutate<T>(_ body: (inout Value) -> T) -> T {
        queue.sync { body(&storage) }
    }
}
