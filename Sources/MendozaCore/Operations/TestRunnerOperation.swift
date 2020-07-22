//
//  TestRunnerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation
import MendozaSharedLibrary

class TestRunnerOperation: BaseOperation<[TestCaseResult]> {
    // An array of TestCases sorted from the longest to the shortest estimated execution time
    var sortedTestCases: [TestCase]?
    var currentResult: [TestCaseResult]?
    var currentRunningTest = [Int: (test: TestCase, start: TimeInterval)]()
    var testRunners: [(testRunner: TestRunner, node: Node)]?

    private var testCasesCount = 0
    private var testCasesCompleted = [TestCase]()

    private let configuration: Configuration
    private let buildTarget: String
    private let testTarget: String
    private let sdk: XcodeProject.SDK
    private let testForStabilityCount: Int
    private let failingTestsRetryCount: Int
    private let testTimeoutSeconds: Int
    private let syncQueue = DispatchQueue(label: String(describing: TestRunnerOperation.self))
    private let verbose: Bool
    private var timeoutBlocks = [Int: CancellableDelayedTask]()
    private var retryCountMap = NSCountedSet()

    private func checkRetryCount(_ testCase: TestCase) -> Int {
        return retryCountMap.count(for: testCase)
    }

    private let eventPlugin: EventPlugin
    private let device: Device

    private enum XcodebuildLineEvent {
        case testSuitedStarted
        case testCaseStart(testCase: TestCase)
        case testCasePassed(duration: Double)
        case testCaseFailed(duration: Double)
        case testCaseCrashed
        case noSpaceOnDevice
        case undefined

        var isTestPassed: Bool {
            switch self {
            case .testCasePassed: return true
            default: return false
            }
        }

        var isTestCrashed: Bool {
            switch self {
            case .testCaseCrashed: return true
            default: return false
            }
        }
    }

    private lazy var pool: ConnectionPool<TestRunner> = {
        guard let sortedTestCases = sortedTestCases else { fatalError("💣 Required field `distributedTestCases` not set") }
        guard let testRunners = testRunners else { fatalError("💣 Required field `testRunner` not set") }

        let input = zip(testRunners, sortedTestCases)
        return makeConnectionPool(sources: input.map { (node: $0.0.node, value: $0.0.testRunner) })
    }()

    init(
        configuration: Configuration,
        buildTarget: String,
        testTarget: String,
        sdk: XcodeProject.SDK,
        testForStabilityCount: Int,
        failingTestsRetryCount: Int,
        testTimeoutSeconds: Int,
        eventPlugin: EventPlugin,
        device: Device,
        verbose: Bool
    ) {
        self.configuration = configuration
        self.buildTarget = buildTarget
        self.testTarget = testTarget
        self.sdk = sdk
        self.testForStabilityCount = testForStabilityCount
        self.failingTestsRetryCount = failingTestsRetryCount
        self.testTimeoutSeconds = testTimeoutSeconds
        self.eventPlugin = eventPlugin
        self.device = device
        self.verbose = verbose
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            var result = currentResult ?? [TestCaseResult]()

            testCasesCount = sortedTestCases?.count ?? 0
            guard testCasesCount > 0 else {
                didEnd?(result)
                return
            }

            if !result.isEmpty {
                print("\n\nℹ️  Repeating failing tests".magenta)
            }

            try pool.execute { [unowned self] executer, source in
                let testRunner = source.value

                let runnerIndex = self.syncQueue.sync { [unowned self] in
                    self.testRunners?.firstIndex { $0.0.id == testRunner.id && $0.0.name == testRunner.name } ?? 0
                }

                while true {
                    let testCases: [TestCase] = self.syncQueue.sync { [unowned self] in
                        guard let testCase = self.sortedTestCases?.first else {
                            return []
                        }

                        self.sortedTestCases?.removeFirst()

                        return [testCase]
                    }

                    guard !testCases.isEmpty else { break }

                    // TODO: Make this configurable via JSON
                    #if DEBUG
                    print("ℹ️  \(self.verbose ? "[\(Date().description)] " : "")Node \(source.node.address) will execute \(testCases.count) tests on \(testRunner.name) {\(runnerIndex)}".magenta)
                    #endif

                    executer.logger?.log(command: "Will launch \(testCases.count) test cases")
                    executer.logger?.log(output: testCases.map { $0.testIdentifier }.joined(separator: "\n"), statusCode: 0)

                    let output = try autoreleasepool {
                        try self.testWithoutBuilding(
                            executer: executer,
                            testTarget: self.testTarget,
                            testCases: testCases,
                            testRunner: testRunner,
                            runnerIndex: runnerIndex
                        )
                    }

                    let xcResultUrl = try self.findTestResultUrl(executer: executer, testRunner: testRunner)

                    // We need to move results because xcodebuild test-without-building shows a weird behaviour not allowing more than 2 xcresults in the same folder.
                    // Repeatedly performing 'xcodebuild test-without-building' results in older xcresults being deleted
                    let resultUrl = Path.results.url.appendingPathComponent(testRunner.id)
                    _ = try executer.capture("mkdir -p '\(resultUrl.path)'; mv '\(xcResultUrl.path)' '\(resultUrl.path)'")

                    var testResults = try self.parseTestResults(output, candidates: testCases, node: source.node.address, xcResultPath: xcResultUrl.path)

                    if let bootstrappingTestResults = try self.handleBootstrappingErrors(output, partialResult: testResults, candidates: testCases, node: source.node.address, xcResultPath: xcResultUrl.path) {
                        testResults += bootstrappingTestResults

                        self.forceResetSimulator(executer: executer, testRunner: testRunner)
                    }

                    self.syncQueue.sync { [unowned self] in
                        // Note: Retry successful tests in order to determine if they are stable
                        let passedTestCases = testResults.filter { $0.status == .passed }.map { TestCase(name: $0.name, suite: $0.suite) }
                        self.enqueueTests(testCases: passedTestCases, retryCount: self.testForStabilityCount).forEach { self.sortedTestCases?.insert($0, at: 0) }

                        // Note: Retry failing tests
                        let failedTestCases = testResults.filter { $0.status == .failed }.map { TestCase(name: $0.name, suite: $0.suite) }
                        self.enqueueTests(testCases: failedTestCases, retryCount: self.failingTestsRetryCount).forEach { self.sortedTestCases?.insert($0, at: 0) }

                        result += testResults
                    }
                }

                try self.copyDiagnosticReports(executer: executer, testRunner: testRunner)
                try self.copyStandardOutputLogs(executer: executer, testRunner: testRunner)
                try self.copySessionLogs(executer: executer, testRunner: testRunner)
                try self.reclaimDiskSpace(executer: executer, testRunner: testRunner)

                #if DEBUG
                print("\nℹ️  Node {\(runnerIndex)} did execute tests in \(formatTime(duration: CFAbsoluteTimeGetCurrent() - self.startTimeInterval))\n".magenta)
                #endif
            }

            didEnd?(result)
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

    private func testWithoutBuilding(executer: Executer, testTarget: String, testCases: [TestCase], testRunner: TestRunner, runnerIndex: Int) throws -> String {
        let testRun = try findTestRun(executer: executer)
        let onlyTesting = testCases.map { "-only-testing:'\(testTarget)/\($0.testIdentifier)'" }.joined(separator: " ")
        let destinationPath = Path.logs.url.appendingPathComponent(testRunner.id).path

        var testWithoutBuilding: String

        switch sdk {
        case .ios:
            testWithoutBuilding = #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination 'platform=iOS Simulator,id=\#(testRunner.id)' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES -destination-timeout 60 test-without-building"#
        case .macos:
            testWithoutBuilding = #"$(xcode-select -p)/usr/bin/xcodebuild -parallel-testing-enabled NO -disable-concurrent-destination-testing -xctestrun '\#(testRun)' -destination 'platform=OS X,arch=x86_64' -derivedDataPath '\#(destinationPath)' \#(onlyTesting) -enableCodeCoverage YES test-without-building"#
        }
        testWithoutBuilding += " || true"

        var partialProgress = ""
        let progressHandler: ((String) -> Void) = { [unowned self] progress in
            let timeoutBlockRunning = self.syncQueue.sync { self.timeoutBlocks[runnerIndex]?.isRunning == true }
            guard !timeoutBlockRunning else {
                return
            }

            self.syncQueue.sync {
                self.timeoutBlocks[runnerIndex]?.cancel()
                self.timeoutBlocks[runnerIndex] = self.makeTimeoutBlock(executer: executer, currentRunning: self.currentRunningTest[runnerIndex], testRunner: testRunner, runnerIndex: runnerIndex)
            }

            partialProgress += progress
            let lines = partialProgress.components(separatedBy: "\n")
            let events = self.parseXcodebuildOutput(lines: lines)


            let currentRunningAndDuration: (Bool) -> (test: TestCase, duration: String)? = { [unowned self] addToCompleted in
                guard let currentRunning = self.currentRunningTest[runnerIndex] else { return nil }

                if addToCompleted {
                    self.testCasesCompleted.append(currentRunning.test)
                }

                let duration = formatTime(duration: CFAbsoluteTimeGetCurrent() - currentRunning.start)

                return (test: currentRunning.test, duration: duration)
            }

            var values = [String: [String]]()

            for (index, event) in events.enumerated() {
                let xcodeEvent = event.xcodeEvent
                let eventValues: [String: String] = event.values

                switch xcodeEvent {
                case .testSuitedStarted:
                    self.syncQueue.sync { [unowned self] in
                        try? self.eventPlugin.run(event: Event(kind: .testSuiteStarted, info: eventValues, values: values), device: self.device)
                    }

                case let .testCaseStart(testCase):
                    self.syncQueue.sync {
                        self.currentRunningTest[runnerIndex] = (test: testCase, start: CFAbsoluteTimeGetCurrent())
                        values["tags"] = testCase.tags
                        values["testCaseIDs"] = testCase.testCaseIDs

                        try? self.eventPlugin.run(event: Event(kind: .testCaseStarted, info: eventValues, values: values), device: self.device)

                        if self.verbose {
                            print(log: "🛫 [\(Date().description)] \(testCase.description) started {\(runnerIndex)}".yellow)
                        }
                    }

                case .testCasePassed:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = currentRunningAndDuration(true) else { return }
                        values["tags"] = currentRunning.test.tags
                        values["testCaseIDs"] = currentRunning.test.testCaseIDs

                        try? self.eventPlugin.run(event: Event(kind: .testPassed, info: eventValues, values: values), device: self.device)

                        self.printOutput(
                            status: xcodeEvent,
                            testCase: currentRunning.test,
                            completedTests: self.testCasesCompleted.count,
                            totalTests: self.testCasesCount,
                            duration: currentRunning.duration,
                            runnerIndex: runnerIndex,
                            verbose: self.verbose
                        )

                        self.currentRunningTest[runnerIndex] = nil
                    }

                case .testCaseFailed:
                    self.syncQueue.sync { [unowned self] in
                        let addToCompleted = index > 0 ? events[index - 1].xcodeEvent.isTestCrashed == false : true

                        guard let currentRunning = currentRunningAndDuration(addToCompleted) else { return }

                        values["tags"] = currentRunning.test.tags
                        values["testCaseIDs"] = currentRunning.test.testCaseIDs

                        try? self.eventPlugin.run(event: Event(kind: .testFailed, info: eventValues, values: values), device: self.device)

                        self.printOutput(
                            status: xcodeEvent,
                            testCase: currentRunning.test,
                            completedTests: self.testCasesCompleted.count,
                            totalTests: self.testCasesCount,
                            duration: currentRunning.duration,
                            runnerIndex: runnerIndex,
                            verbose: self.verbose
                        )

                        self.currentRunningTest[runnerIndex] = nil
                    }

                case .testCaseCrashed:
                    self.syncQueue.sync { [unowned self] in
                        guard let currentRunning = currentRunningAndDuration(true) else { return }

                        values["tags"] = currentRunning.test.tags
                        values["testCaseIDs"] = currentRunning.test.testCaseIDs

                        try? self.eventPlugin.run(event: Event(kind: .testCrashed, info: eventValues, values: values), device: self.device)

                        self.printOutput(
                            status: xcodeEvent,
                            testCase: currentRunning.test,
                            completedTests: self.testCasesCompleted.count,
                            totalTests: self.testCasesCount,
                            duration: currentRunning.duration,
                            runnerIndex: runnerIndex,
                            verbose: self.verbose
                        )

                        self.currentRunningTest[runnerIndex] = nil
                    }

                case .noSpaceOnDevice:
                    try? self.eventPlugin.run(event: Event(kind: .testCrashed, info: eventValues, values: [:]), device: self.device)
                    fatalError("💥  No space left on \(executer.address). If you're using a RAM disk in Mendoza's configuration consider increasing size")
                    
                case .undefined:
                    break
                }
            }

            partialProgress = lines.last ?? ""
        }

        var output = ""
        for shouldRetry in [true, false] {
            syncQueue.sync {
                self.timeoutBlocks[runnerIndex]?.cancel()
                self.timeoutBlocks[runnerIndex] = self.makeTimeoutBlock(executer: executer, currentRunning: self.currentRunningTest[runnerIndex], testRunner: testRunner, runnerIndex: runnerIndex)
            }

            output = try executer.execute(testWithoutBuilding, progress: progressHandler) { result, originalError in
                try self.assertAccessibilityPermissions(in: result.output)
                throw originalError
            }

            syncQueue.sync { timeoutBlocks[runnerIndex]?.cancel() }

            // xcodebuild returns 0 even on ** TEST EXECUTE FAILED ** when missing
            // accessibility permissions or other errors like the bootstrapping onese we check in testsDidFailToStart
            try assertAccessibilityPermissions(in: output)

            guard !testsDidFailBootstrapping(in: output) else {
                Thread.sleep(forTimeInterval: 5.0)
                partialProgress = ""

                guard shouldRetry else {
                    throw Error("Tests failed boostrapping on node \(testRunner.name)-\(testRunner.id)")
                }

                continue
            }

            guard !testDidFailBecauseOfDamagedBuild(in: output) else {
                switch AddressType(address: executer.address) {
                case .local:
                    _ = try executer.execute("rm -rf '\(Path.build.rawValue)' || true")
                    // To be improved
                    throw Error("Tests failed because of damaged build folder, please try rerunning the build again")
                case .remote:
                    break
                }

                break
            }

            break
        }

        return output
    }

    private func parseXcodebuildOutput(lines: [String]) -> [(xcodeEvent: XcodebuildLineEvent, values: [String: String])] {
        let xcodeParser = Parser()

        var output: [(xcodeEvent: XcodebuildLineEvent, values: [String: String])] = []

        for line in lines {
            var xcodebuildEvent: XcodebuildLineEvent
            var values: [String: String] = [:]

            let outputData = xcodeParser.parse(line: line, colored: false)
            values = outputData.value

            switch outputData.pattern {
            case .noSpaceOnDevice:
                xcodebuildEvent = .noSpaceOnDevice

            case .testSuiteStart:
                xcodebuildEvent = .testSuitedStarted
                values = outputData.value

            case .testCaseStarted:
                let testCaseSuite = values["testSuite"] ?? ""
                let testCaseName = values["testCase"] ?? ""
                let testCase = TestCase(name: testCaseName, suite: testCaseSuite)

                xcodebuildEvent = .testCaseStart(testCase: testCase)

            case .testCasePassed, .parallelTestCasePassed:
                let duration = Double(values["time"] ?? "-1") ?? -1
                xcodebuildEvent = .testCasePassed(duration: duration)

            case .failingTest, .uiFailingTest, .parallelTestCaseFailed:
                let duration = Double(values["time"] ?? "-1") ?? -1
                xcodebuildEvent = .testCaseFailed(duration: duration)

            case .restartingTests, .encounteredAnError, .checkingForCrashReports:
                xcodebuildEvent = .testCaseCrashed

            case .encounteredAnSimulatorError, .testingFailed:
                xcodebuildEvent = .testCaseFailed(duration: -1)

            default:
                xcodebuildEvent = .undefined
            }

            output.append((xcodebuildEvent, values))
        }

        return output
    }

    private func parseTestResults(_ output: String, candidates: [TestCase], node: String, xcResultPath: String) throws -> [TestCaseResult] {
        let resultPath = xcResultPath.replacingOccurrences(of: "\(Path.logs.rawValue)/", with: "")

        var result = [TestCaseResult]()

        let lines = output.components(separatedBy: "\n")
        let xcodeEvents = parseXcodebuildOutput(lines: lines)

        var currentCandidate: TestCase?

        for event in xcodeEvents {
            switch event.xcodeEvent {
            case .testSuitedStarted:
                break

            case let .testCaseStart(test):
                guard let matchingCandidate = candidates.first(where: { $0 == test }) else {
                    if verbose { print("⚠️  did not find test results for `\(test.description)`\n") }
                    break
                }

                currentCandidate = matchingCandidate

            case let .testCasePassed(duration), let .testCaseFailed(duration):
                guard let currentCandidate = currentCandidate else { break }

                let testCaseResults = TestCaseResult(
                    node: node,
                    xcResultPath: resultPath,
                    suite: currentCandidate.suite,
                    name: currentCandidate.name,
                    status: event.xcodeEvent.isTestPassed ? .passed : .failed,
                    duration: duration,
                    testCaseIDs: currentCandidate.testCaseIDs,
                    testTags: currentCandidate.tags,
                    message: event.xcodeEvent.isTestPassed ? "" : event.values["reason"] ?? ""
                )

                if let index = result.firstIndex(where: { $0 == testCaseResults }) {
                    result.remove(at: index) // Remove crash result if previously added
                }
                result.append(testCaseResults)

            case .testCaseCrashed:
                guard let currentCandidate = currentCandidate else { break }

                let testCaseResults = TestCaseResult(
                    node: node,
                    xcResultPath: resultPath,
                    suite: currentCandidate.suite,
                    name: currentCandidate.name,
                    status: .failed,
                    duration: -1,
                    testCaseIDs: currentCandidate.testCaseIDs,
                    testTags: currentCandidate.tags,
                    message: ""
                )

                result.append(testCaseResults)

            case .noSpaceOnDevice:
                throw Error("💥  No space left on device. If you're using a RAM disk in Mendoza's configuration consider increasing size".red)

            case .undefined:
                break
            }
        }

        return result
    }

    private func handleBootstrappingErrors(_ output: String, partialResult: [TestCaseResult], candidates: [TestCase], node: String, xcResultPath: String) throws -> [TestCaseResult]? {
        let boostrappingError = "Application failed preflight checks"

        let resultPath = xcResultPath.replacingOccurrences(of: "\(Path.logs.rawValue)/", with: "")

        if output.contains(boostrappingError) {
            let failedCandidates = candidates.filter { candidate in
                partialResult.contains(where: { candidate.suite == $0.suite && candidate.testIdentifier == $0.testCaseIdentifier }) == false
            }

            return failedCandidates.map {
                TestCaseResult(
                    node: node,
                    xcResultPath: resultPath,
                    suite: $0.suite,
                    name: $0.name,
                    status: .failed,
                    duration: -1,
                    testCaseIDs: $0.testCaseIDs,
                    testTags: $0.tags,
                    message: ""
                )
            }
        }

        return nil
    }

    private func makeTimeoutBlock(executer: Executer, currentRunning: @autoclosure @escaping () -> (test: TestCase, start: TimeInterval)?, testRunner: TestRunner, runnerIndex: Int) -> CancellableDelayedTask {
        let task = CancellableDelayedTask(delay: TimeInterval(testTimeoutSeconds), queue: syncQueue)

        task.run { [unowned self] in
            if let currentRunning = currentRunning() {
                print("⏰ \(currentRunning.test.description) timed out {\(runnerIndex)} in \(Int(CFAbsoluteTimeGetCurrent() - currentRunning.start))s".red)
            } else {
                print("⏰ Unknown test timed out {\(runnerIndex)}".red)
            }

            // - NOTE:
            // To stop tests that time out we're force resetting simulators.
            // This abrupt way of stopping tests will have as a consequence that
            // no data related to the test will be written to the output xcresult
            DispatchQueue.global(qos: .userInitiated).async {
                self.forceResetSimulator(executer: executer, testRunner: testRunner)
            }
        }

        return task
    }

    private func forceResetSimulator(executer: Executer, testRunner: TestRunner) {
        guard let simulatorExecuter = try? executer.clone() else { return }

        let proxy = CommandLineProxy.Simulators(executer: simulatorExecuter, verbose: true)
        let simulator = Simulator(id: testRunner.id, name: "Simulator", device: Device.defaultInit())

        // There's no better option than shutting down simulator at this point
        // xcodebuild will take care to boot simulator again and continue testing
        try? proxy.shutdown(simulator: simulator)
        try? proxy.boot(simulator: simulator)
    }

    private func enqueueTests(testCases: [TestCase], retryCount: Int) -> [TestCase] {
        var retryTestCases = [TestCase]()
        for testCase in testCases {
            if retryCountMap.count(for: testCase) < retryCount {
                retryCountMap.add(testCase)
                retryTestCases.insert(testCase, at: 0)
                testCasesCount += 1

                if verbose {
                    print("🔁  Renqueuing \(testCase), retry count: \(retryCountMap.count(for: testCase))".yellow)
                }
            }
        }

        return retryTestCases
    }

    private func findTestRun(executer: Executer) throws -> String {
        let testBundlePath = Path.testBundle.rawValue

        let testRuns = try executer.execute("find '\(testBundlePath)' -type f -name '\(configuration.scheme)*.xctestrun'").components(separatedBy: "\n")
        guard let testRun = testRuns.first, !testRun.isEmpty else { throw Error("No test bundle found", logger: executer.logger) }
        guard testRuns.count == 1 else { throw Error("Too many xctestrun bundles found:\n\(testRuns)", logger: executer.logger) }

        return testRun
    }

    private func findTestResultUrl(executer: Executer, testRunner: TestRunner) throws -> URL {
        var xcresultPath: String
        let resultPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        let testResults = try executer.execute("find '\(resultPath)' -type d -name '*.xcresult'").components(separatedBy: "\n")

        let testResultsPaths = try testResults.compactMap { testResult -> String? in
            let validateOutput = try executer.capture("xcrun xcresulttool get --path '\(testResult)'")

            if validateOutput.status == 0 {
                return testResult
            }

            return nil
        }

        guard
            let testResult = testResultsPaths.first, !testResult.isEmpty else {
                throw Error("No test result found", logger: executer.logger)
        }

        if testResultsPaths.count > 1 {
            let timeStamp = Int64(Date().timeIntervalSince1970 * 1000)

            let mergedDestinationPath = "\(resultPath)/Test\(timeStamp)\(Environment.xcresultType)"
            let mergeCmd = "xcrun xcresulttool merge " + testResultsPaths.map { $0.replacingOccurrences(of: " ", with: #"\ "#) }.joined(separator: " ") + " --output-path '\(mergedDestinationPath)'"
            let output = try executer.execute(mergeCmd)

            guard let path = output.components(separatedBy: "Merged to:").last else {
                throw Error("Failed to get merged xcresult Path", logger: executer.logger)
            }

            xcresultPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            xcresultPath = testResult
        }

        return URL(fileURLWithPath: xcresultPath)
    }

    private func copyDiagnosticReports(executer: Executer, testRunner: TestRunner) throws {
        let sourcePath1 = "~/Library/Logs/DiagnosticReports/\(buildTarget)*"
        let sourcePath2 = "~/Library/Logs/DiagnosticReports/\(testTarget)*"

        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("DiagnosticReports").path

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        _ = try executer.execute("cp '\(sourcePath1)' \(destinationPath) || true")
        _ = try executer.execute("cp '\(sourcePath2)' \(destinationPath) || true")
    }

    private func copyStandardOutputLogs(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("StandardOutputAndStandardError").path
        let sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -name 'StandardOutputAndStandardError*.txt'").components(separatedBy: "\n")

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)' || true") }
    }

    private func copySessionLogs(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("Session").path
        let sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -name 'Session-\(testTarget)*.log'").components(separatedBy: "\n")

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try sourcePaths.forEach { _ = try executer.execute("cp '\($0)' '\(destinationPath)' || true") }
    }

    private func reclaimDiskSpace(executer: Executer, testRunner: TestRunner) throws {
        // remove all Diagnostiscs folder inside .xcresult which contain some largish log files we don't need
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        var sourcePaths = try executer.execute("find \(testRunnerLogUrl.path) -type d -name 'Diagnostics'").components(separatedBy: "\n")
        sourcePaths = sourcePaths.filter { $0.contains(".xcresult/") }

        try sourcePaths.forEach {
            print(#"rm -rf "\#($0)"#)
            _ = try executer.execute(#"rm -rf "\#($0)""#)
        }
    }

    private func assertAccessibilityPermissions(in output: String) throws {
        if output.contains("does not have permission to use Accessibility") {
            throw Error("Unable to run UI Tests because Xcode Helper does not have permission to use Accessibility. To enable UI testing, go to the Security & Privacy pane in System Preferences, select the Privacy tab, then select Accessibility, and add Xcode Helper to the list of applications allowed to use Accessibility")
        }
    }

    private func testsDidFailBootstrapping(in output: String) -> Bool {
        return output.contains("Test runner exited before starting test execution")
    }

    private func testDidFailBecauseOfDamagedBuild(in output: String) -> Bool {
        return output.contains("The application may be damaged or incomplete")
    }

    private func printOutput(status: XcodebuildLineEvent?, testCase: TestCase, completedTests: Int, totalTests: Int, duration: String, runnerIndex: Int, verbose: Bool) {
        var log = [String]()
        var updateTextColour = false
        var logOutput: String

        switch status {
        case .testCasePassed(duration: _):
            verbose ? log.append("[Passed]".green) : log.append("✓".green)
        case .testCaseFailed(duration: _):
            updateTextColour = true
            verbose ? log.append("[Failed]") : log.append("𝘅")

        case .testCaseCrashed:
            updateTextColour = true
            verbose ? log.append("[Crashed]") : log.append("💥")

        default:
            updateTextColour = false
        }

        if verbose {
            log.append("[\(Date().description)]")
        }

        log.append(testCase.description)
        log.append("(\(duration))")
        log.append("[\(completedTests)/\(totalTests)]")

        let retryCount = checkRetryCount(testCase)

        if retryCount > 0 {
            log.append("(\(retryCount) retries)")
        }

        if verbose {
            log.append("{\(runnerIndex)}")
        }

        logOutput = log.joined(separator: " ")

        if updateTextColour {
            logOutput = logOutput.red
        }

        print(log: logOutput)
    }
}
