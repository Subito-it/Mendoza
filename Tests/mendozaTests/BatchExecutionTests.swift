import Foundation
@testable import mendoza
import XCTest

final class BatchExecutionTests: XCTestCase {
    private let a = TestCase(name: "testA", suite: "ExampleTests")
    private let b = TestCase(name: "testB", suite: "ExampleTests")
    private let c = TestCase(name: "testC", suite: "ExampleTests")

    private func state() -> BatchTestState {
        BatchTestState(tests: [a, b], node: "localhost", runnerName: "Simulator", runnerIdentifier: "runner", now: 0)
    }

    func testParserRetainsVerdictIdentityAndSkipCompatibility() {
        let parser = BatchOutputParser(target: "UI Tests")
        XCTAssertEqual(parser.event("Test Case '-[UI_Tests.ExampleTests testB]' started."), .started(b))
        XCTAssertEqual(parser.event("Test Case '-[UI_Tests.ExampleTests testA]' passed (1.0 seconds)."), .finished(a, passed: true))
        XCTAssertEqual(parser.event("Test Case '-[UI_Tests.ExampleTests testA]' skipped (0.0 seconds)."), .skipped(a))
        XCTAssertEqual(parser.event("Test Case '-[UI_Tests.ExampleTests testB]' exceeded execution time allowance"), .interrupted(b))
        XCTAssertNil(parser.event("Test Case '-[Other.ExampleTests testA]' passed (1.0 seconds)."))
    }

    func testFramerHandlesEveryByteBoundaryAndFinalUnterminatedLine() {
        let lines = ["Test Case '-[UITests.ExampleTests testA]' started.", "Unicode 🧪 café", "last"]
        let bytes = Data(lines.joined(separator: "\r\n").utf8)
        for boundary in 0 ... bytes.count {
            var framer = BatchLineFramer()
            let first = framer.append(bytes.prefix(boundary))
            let second = framer.append(bytes.dropFirst(boundary), flush: true)
            XCTAssertEqual(first + second, lines)
        }
    }

    func testReorderedTestsHaveIndependentTimingAndTerminalDeduplication() {
        var value = state()
        value.consume(.started(b), at: 2)
        value.output(at: 3)
        value.consume(.finished(b, passed: false), at: 4)
        value.consume(.finished(b, passed: false), at: 4)
        value.consume(.started(a), at: 6)
        value.output(at: 8)
        value.consume(.finished(a, passed: true), at: 9)
        value.complete(at: 20)
        XCTAssertEqual(value.results.map(\.name), ["testB", "testA"])
        XCTAssertEqual(value.results.map(\.duration), [2, 3])
        XCTAssertEqual(value.results.map(\.maxStdOutIdleTime), [1, 2])
        XCTAssertTrue(value.remaining.isEmpty)
        XCTAssertNil(value.abortReason)
    }

    func testWatchdogStopsWholeInvocationAndPreservesCompletedSibling() {
        var value = state()
        value.consume(.started(a), at: 1)
        value.consume(.finished(a, passed: true), at: 2)
        value.consume(.started(b), at: 3)
        value.checkTimeout(now: 9, idleLimit: 5, executionLimit: nil)
        value.consume(.finished(b, passed: true), at: 10)
        value.complete(at: 11)
        XCTAssertEqual(value.results.map(\.status), [.passed, .failed])
        XCTAssertEqual(value.abortReason, "Active test stdout timeout")
        XCTAssertTrue(value.remaining.isEmpty)
    }

    func testInterruptedFirstTestReturnsSiblingWithoutAttempt() {
        var value = state()
        value.consume(.started(a), at: 1)
        value.consume(.interrupted(a), at: 2)
        value.consume(.started(b), at: 3)
        value.complete(at: 4)
        XCTAssertEqual(value.results.map(\.name), [a.name])
        XCTAssertEqual(value.remaining, [b])
    }

    func testLaunchFailureConsumesOnlyOneAttempt() {
        var value = state()
        value.complete(at: 10)
        XCTAssertEqual(value.results.count, 1)
        XCTAssertEqual(value.results.first?.status, .failed)
        XCTAssertEqual(value.remaining, [b])
    }

    func testNoOutputTimerDuringBetweenTestsOrFinalization() {
        var value = state()
        value.consume(.started(a), at: 1)
        value.consume(.finished(a, passed: true), at: 2)
        value.checkTimeout(now: 30, idleLimit: 1, executionLimit: nil)
        XCTAssertNil(value.abortReason)
        value.consume(.started(b), at: 31)
        value.consume(.finished(b, passed: true), at: 32)
        value.checkTimeout(now: 200, idleLimit: 1, executionLimit: nil)
        XCTAssertNil(value.abortReason)
        value.checkTimeout(now: 933, idleLimit: 1, executionLimit: nil)
        XCTAssertNotNil(value.abortReason)
        XCTAssertEqual(value.results.map(\.status), [.passed, .passed])
    }

    func testExecutionTimeoutDespiteContinuousOutput() {
        var value = state()
        value.consume(.started(a), at: 1)
        value.output(at: 10)
        value.checkTimeout(now: 10, idleLimit: 5, executionLimit: 8)
        XCTAssertEqual(value.abortReason, "Active test execution timeout")
    }

    func testUnknownOrRepeatedStartAbortsWithoutFabricatingAPass() {
        var value = state()
        value.consume(.started(c), at: 1)
        value.complete(at: 2)
        XCTAssertNotNil(value.abortReason)
        XCTAssertEqual(value.results.first?.status, .failed)
        var repeated = state()
        repeated.consume(.started(a), at: 1)
        repeated.consume(.finished(a, passed: true), at: 2)
        repeated.consume(.started(a), at: 3)
        XCTAssertNotNil(repeated.abortReason)
        XCTAssertEqual(repeated.remaining, [b])
    }

    func testLateNamedCrashDoesNotFailActiveSibling() {
        var value = state()
        value.consume(.started(a), at: 1)
        value.consume(.finished(a, passed: false), at: 2)
        value.consume(.started(b), at: 3)
        value.consume(.interrupted(a), at: 4)
        XCTAssertEqual(value.active, b)
        XCTAssertNil(value.abortReason)
    }

    func testSkipWithoutStartPreservesPublicPassedStatus() {
        var value = state()
        value.consume(.skipped(a), at: 1)
        XCTAssertEqual(value.results.first?.status, .passed)
        XCTAssertEqual(value.results.first?.duration, 0)
        XCTAssertNil(value.abortReason)
        XCTAssertEqual(value.remaining, [b])
    }

    func testNewSelectedStartClosesInterruptedActiveTest() {
        var value = state()
        value.consume(.started(a), at: 1)
        value.consume(.started(b), at: 2)
        value.consume(.finished(b, passed: true), at: 3)
        XCTAssertEqual(value.results.map(\.status), [.failed, .passed])
        XCTAssertNil(value.abortReason)
    }

    func testQueueRetriesAndUnstartedTestsRemainSingletons() {
        let queue = TestQueue(testCases: [a, b, c], maxRetryCount: 1)
        XCTAssertEqual(queue.dequeueBatch(for: 0, maximumCount: 2), [a, b])
        queue.returnUnstarted([b])
        XCTAssertTrue(queue.enqueueForRetry(a, excludedRunnerIndexes: [0]))
        XCTAssertEqual(queue.dequeueBatch(for: 0, maximumCount: 2), [b])
        XCTAssertEqual(queue.dequeueBatch(for: 1, maximumCount: 2), [a])
        XCTAssertEqual(queue.dequeueBatch(for: 0, maximumCount: 2), [c])
        XCTAssertEqual(queue.retryCount(for: b), 0)
        XCTAssertEqual(queue.retryCount, 1)
        XCTAssertFalse(queue.enqueueForRetry(a, excludedRunnerIndexes: []))
    }

    func testConcurrentReservationsLoseOrDuplicateNoTests() {
        let tests = (0 ..< 2_000).map { TestCase(name: "test\($0)", suite: "Suite") }
        let queue = TestQueue(testCases: tests, maxRetryCount: 0)
        let lock = NSLock()
        var reserved = [TestCase]()
        DispatchQueue.concurrentPerform(iterations: 48) { runner in
            while true {
                let batch = queue.dequeueBatch(for: runner, maximumCount: 2)
                if batch.isEmpty {
                    break
                }
                lock.lock()
                reserved += batch
                lock.unlock()
            }
        }
        XCTAssertEqual(reserved.count, 2_000)
        XCTAssertEqual(Set(reserved), Set(tests))
    }

    func testOldTestingConfigurationRoundTripsWithoutNewKey() throws {
        let json = """
        {"killSimulatorProcesses":false,"alwaysRebootSimulators":false,"autodeleteSlowDevices":false,
        "extractIndividualTestCoverage":true,"extractTestCoveredFiles":true,"clearDerivedDataOnCompilationFailure":false,
        "skipResultMerge":false,"disabledSimulatorServices":[],"collectTestDiagnosticsOnFailure":false}
        """
        var config = try JSONDecoder().decode(Configuration.Testing.self, from: Data(json.utf8))
        XCTAssertEqual(config.effectiveTestBatchSize, 1)
        try config.validateBatchSize()
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        XCTAssertNil(encoded["testBatchSize"])
        for value in [-1, 0, 3, 100] {
            config.testBatchSize = value
            XCTAssertThrowsError(try config.validateBatchSize())
        }
        config.testBatchSize = 2
        try config.validateBatchSize()
    }

    private func request(directory: String, idle: Int? = nil) -> BatchRequest {
        BatchRequest(version: 1, identifier: "example", tests: [a, b], target: "UITests", node: "localhost", runnerName: "Simulator", runnerIdentifier: "runner", xctestrun: "/tmp/example.xctestrun", directory: directory, resultPath: directory + "/result.xcresult", idleTimeout: idle, executionTimeout: nil, collectDiagnostics: false, appBundleIdentifier: "example.app", testBundleIdentifier: "example.tests")
    }

    func testCommandHasBothSelectionsAndAnExplicitSharedResult() {
        let value = request(directory: "/tmp/example")
        XCTAssertEqual(value.arguments.filter { $0.hasPrefix("-only-testing:") }, ["-only-testing:UITests/ExampleTests/testA", "-only-testing:UITests/ExampleTests/testB"])
        XCTAssertTrue(value.arguments.contains(value.resultPath))
        XCTAssertEqual(value.arguments.filter { $0 == "-resultBundlePath" }.count, 1)
    }

    func testWorkerReadsChunkedReorderedOutputAndNonzeroExit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = """
        printf "Test Case '-[UITests.ExampleTests testB]' "
        printf "started.\\nTest Case '-[UITests.ExampleTests testB]' failed (1.0 seconds).\\n"
        printf "Test Case '-[UITests.ExampleTests testA]' started.\\n"
        printf "Test Case '-[UITests.ExampleTests testA]' passed (1.0 seconds)."
        exit 65
        """
        var previews = [TestCaseResult]()
        let result = try BatchWorker.execute(request(directory: directory.path), executable: "/bin/sh", arguments: ["-c", script], emit: { previews.append($0) })
        XCTAssertEqual(result.exitStatus, 65)
        XCTAssertEqual(result.results.map(\.status), [.failed, .passed])
        XCTAssertEqual(previews.count, 2)
        XCTAssertTrue(result.unstarted.isEmpty)
    }

    func testWorkerIdleTimeoutKillsOnlyItsProcessGroupAndDefersSibling() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["60"]
        try unrelated.run()
        defer { unrelated.terminate(); unrelated.waitUntilExit() }
        let script = """
        echo $$ > '\(directory.path)/pid'
        printf "Test Case '-[UITests.ExampleTests testA]' started.\\n"
        trap '' TERM INT
        while :; do sleep 1; done
        """
        let result = try BatchWorker.execute(request(directory: directory.path, idle: 1), executable: "/bin/sh", arguments: ["-c", script], emit: { _ in })
        XCTAssertEqual(result.results.map(\.status), [.failed])
        XCTAssertEqual(result.unstarted, [b])
        XCTAssertEqual(result.interruption, "Active test stdout timeout")
        XCTAssertTrue(unrelated.isRunning)
        let pidText = try String(contentsOf: directory.appendingPathComponent("pid")).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(Int32(pidText))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testCollectorUpdatesEverySharedRowAndPreservesMissingArtifacts() {
        var value = state()
        value.consume(.started(a), at: 1)
        value.consume(.finished(a, passed: true), at: 2)
        value.consume(.started(b), at: 3)
        value.consume(.finished(b, passed: true), at: 4)
        var rows = value.results
        rows[0].xcResultPath = "/tmp/mendoza/results/runner/batch.xcresult"
        rows[1].xcResultPath = rows[0].xcResultPath
        rows.append(TestCaseResult.defaultInit())
        TestCollectorOperation.updateBatchResultPaths(&rows, sourcePath: "/destination/runner/batch.xcresult", destinationPath: "results/0.xcresult")
        XCTAssertEqual(rows.map(\.xcResultPath), ["results/0.xcresult", "results/0.xcresult", ""])
    }

    func testWorkerCancellationUsesSameBoundedInterruptionPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = """
        printf "Test Case '-[UITests.ExampleTests testA]' started.\\n"
        touch '\(directory.path)/cancel'
        sleep 60
        """
        let result = try BatchWorker.execute(request(directory: directory.path), executable: "/bin/sh", arguments: ["-c", script], emit: { _ in })
        XCTAssertEqual(result.interruption, "Batch cancelled")
        XCTAssertEqual(result.results.count, 1)
        XCTAssertEqual(result.results.first?.status, .failed)
        XCTAssertEqual(result.unstarted, [b])
    }

    func testRepetitionPreflightRejectsNestedTestPlanSettings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let invalid: [String: Any] = ["TestConfigurations": [["TestTargets": [["RetryTestsOnFailure": true]]]]]
        try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0).write(to: url)
        XCTAssertThrowsError(try BatchWorker.validateTestRun(url.path))
        try PropertyListSerialization.data(fromPropertyList: ["TestConfigurations": [["TestRepetitionMode": "none"]]], format: .xml, options: 0).write(to: url)
        XCTAssertNoThrow(try BatchWorker.validateTestRun(url.path))
    }

    func testStrictCoverageMergePreservesInputsWhenLLVMRejectsThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first profile.profdata")
        let second = directory.appendingPathComponent("second.profdata")
        let bytes = Data("deliberately invalid profile".utf8)
        try bytes.write(to: first)
        try bytes.write(to: second)
        let merger = CodeCoverageMerger(executer: LocalExecuter())
        XCTAssertThrowsError(try merger.merge(coverageFiles: [first.path, second.path], strict: true))
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        XCTAssertEqual(try Data(contentsOf: second), bytes)
    }

    func testBatchCleanerCollectsEveryMembersAttachmentsAndAcceptsEmptyArrays() {
        let first: [String: Any] = ["summaryRef": ["id": ["_value": "test-a"]], "payloadRef": ["id": ["_value": "image-a"]]]
        let second: [String: Any] = ["summaryRef": ["id": ["_value": "test-b"]], "payloadRef": ["id": ["_value": "image-b"]]]
        let object: [String: Any] = ["subtests": ["_values": [first, second]], "analyzerWarningSummaries": ["_type": ["_name": "Array"]]]
        let references = BatchXCResultCleaner.references(in: object)
        XCTAssertEqual(references.objects, ["test-a", "test-b"])
        XCTAssertEqual(references.attachments, ["image-a", "image-b"])
    }
}
