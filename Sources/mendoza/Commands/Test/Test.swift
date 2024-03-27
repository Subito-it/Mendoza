//
//  Test.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

class Test {
    typealias RunOperation = LoggedOperation & BenchmarkedOperation

    var didFail: ((Swift.Error) -> Void)?

    // swiftlint:disable:next large_tuple
    private let configuration: ModernConfiguration
    private let eventPlugin: EventPlugin
    private let pluginUrl: URL?
    private let syncQueue = DispatchQueue(label: String(describing: Test.self))
    private let timestamp: String
    private var observers = [NSKeyValueObservation]()

    init(configuration: ModernConfiguration, pluginUrl: URL?) throws {
        self.configuration = configuration
        self.pluginUrl = pluginUrl

        eventPlugin = EventPlugin(baseUrl: pluginUrl, plugin: configuration.plugins)

        timestamp = Test.currentTimestamp()
    }

    func run() throws {
        print("ℹ️  Dispatching on".magenta.bold)
        let nodes = Array(Set(configuration.nodes.map(\.address))).sorted()
        print(nodes.joined(separator: "\n").magenta)

        let git = Git(executer: LocalExecuter())
        let gitStatus = try git.status()

        let queue = OperationQueue()

        let testSessionResult = TestSessionResult()
        let arguments: [String?] = [configuration.device?.name,
                                    configuration.device?.runtime,
                                    configuration.building.filePatterns.include.sorted().joined(separator: ","),
                                    configuration.building.filePatterns.exclude.sorted().joined(separator: ","),
                                    configuration.plugins?.data]

        testSessionResult.launchArguments = arguments.compactMap { $0 }.joined(separator: " ")

        let operations = try makeOperations(gitStatus: gitStatus, testSessionResult: testSessionResult, sdk: configuration.building.sdk)

        queue.addOperations(operations, waitUntilFinished: true)

        tearDown(operations: operations, testSessionResult: testSessionResult, error: nil)
    }

    private func makeOperations(gitStatus: GitStatus, testSessionResult: TestSessionResult, sdk: String) throws -> [RunOperation] {
        let resultDestinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.resultFoldername)".pathExpandingTilde()

        let filePatterns = configuration.building.filePatterns
        let codeCoveragePathEquivalence = configuration.testing.codeCoveragePathEquivalence
        let clearDerivedDataOnCompilationFailure = configuration.testing.clearDerivedDataOnCompilationFailure

        guard let device = configuration.device else {
            // FIXME: - To support macOS we should not required device
            throw Error("Unexpected missing device")
        }

        let gitBaseUrl = gitStatus.url
        let project = try localProject(baseUrl: gitBaseUrl, path: configuration.building.projectPath)

        let uniqueNodes = configuration.nodes.unique()
        let targets = try project.getTargetsInScheme(configuration.building.scheme)
        let testTargetSourceFiles = try project.testTargetSourceFilePaths(scheme: configuration.building.scheme)

        let productNames = project.getProductNames()

        let preCompilationPlugin = PreCompilationPlugin(baseUrl: pluginUrl, plugin: configuration.plugins)
        let postCompilationPlugin = PostCompilationPlugin(baseUrl: pluginUrl, plugin: configuration.plugins)
        let testExtractionPlugin = TestExtractionPlugin(baseUrl: pluginUrl, plugin: configuration.plugins)
        let testSortingPlugin = TestSortingPlugin(baseUrl: pluginUrl, plugin: configuration.plugins)
        let tearDownPlugin = TearDownPlugin(baseUrl: pluginUrl, plugin: configuration.plugins)

        let initialSetupOperation = InitialSetupOperation(resultDestination: configuration.resultDestination, nodes: uniqueNodes, xcodeBuildNumber: configuration.building.xcodeBuildNumber)
        let validationOperation = ValidationOperation(nodes: configuration.nodes)
        let macOsValidationOperation = MacOsValidationOperation(nodes: configuration.nodes)
        let localSetupOperation = LocalSetupOperation(clearDerivedDataOnCompilationFailure: clearDerivedDataOnCompilationFailure)
        let remoteSetupOperation = RemoteSetupOperation(nodes: uniqueNodes)
        let compileOperation = CompileOperation(building: configuration.building, git: gitStatus, baseUrl: gitBaseUrl, project: project, scheme: configuration.building.scheme, preCompilationPlugin: preCompilationPlugin, postCompilationPlugin: postCompilationPlugin, clearDerivedDataOnCompilationFailure: clearDerivedDataOnCompilationFailure)
        let testExtractionOperation = TestExtractionOperation(baseUrl: gitBaseUrl, testTargetSourceFiles: testTargetSourceFiles, filePatterns: filePatterns, device: device, plugin: testExtractionPlugin)
        let testSortingOperation = TestSortingOperation(device: device, plugin: testSortingPlugin, verbose: configuration.verbose)
        let simulatorSetupOperation = SimulatorSetupOperation(buildBundleIdentifier: configuration.building.buildBundleIdentifier, testBundleIdentifier: configuration.building.testBundleIdentifier, nodes: uniqueNodes, device: device, autodeleteSlowDevices: configuration.testing.autodeleteSlowDevices, verbose: configuration.verbose)
        let processKillerOperation = ProcessKillerOperation(nodes: uniqueNodes)
        let distributeTestBundleOperation = DistributeTestBundleOperation(nodes: uniqueNodes)
        let testRunnerOperation = TestRunnerOperation(configuration: configuration, destinationPath: resultDestinationPath, testTarget: targets.test.name, productNames: productNames)
        let testCollectorOperation = TestCollectorOperation(resultDestination: configuration.resultDestination, nodes: configuration.nodes, mergeResults: !configuration.testing.skipResultMerge, destinationPath: resultDestinationPath, productNames: productNames)

        let codeCoverageCollectionOperation = CodeCoverageCollectionOperation(resultDestination: configuration.resultDestination, buildBundleIdentifier: configuration.building.buildBundleIdentifier, pathEquivalence: codeCoveragePathEquivalence, baseUrl: gitBaseUrl, timestamp: timestamp)
        let cleanupOperation = CleanupOperation(resultDestination: configuration.resultDestination, timestamp: timestamp)
        let simulatorTearDownOperation = SimulatorTearDownOperation(nodes: uniqueNodes, verbose: configuration.verbose)
        let tearDownOperation = TearDownOperation(resultDestination: configuration.resultDestination, nodes: configuration.nodes, git: gitStatus, timestamp: timestamp, mergeResults: !configuration.testing.skipResultMerge, autodeleteSlowDevices: configuration.testing.autodeleteSlowDevices, plugin: tearDownPlugin)

        var operations: [RunOperation] =
            [initialSetupOperation,
             compileOperation,
             validationOperation,
             macOsValidationOperation,
             localSetupOperation,
             remoteSetupOperation,
             testExtractionOperation,
             testSortingOperation,
             simulatorSetupOperation,
             distributeTestBundleOperation,
             testRunnerOperation,
             testCollectorOperation,
             codeCoverageCollectionOperation,
             simulatorTearDownOperation,
             cleanupOperation,
             tearDownOperation]

        switch XcodeProject.SDK(rawValue: sdk)! {
        case .ios:
            macOsValidationOperation.cancel()
        case .macos:
            simulatorTearDownOperation.cancel()
            simulatorSetupOperation.cancel()
        }

        macOsValidationOperation.addDependency(initialSetupOperation)
        validationOperation.addDependency(initialSetupOperation)
        localSetupOperation.addDependency(initialSetupOperation)

        compileOperation.addDependency(localSetupOperation)

        remoteSetupOperation.addDependency(validationOperation)

        testExtractionOperation.addDependency(localSetupOperation)

        simulatorSetupOperation.addDependencies([localSetupOperation, remoteSetupOperation])
        processKillerOperation.addDependency(simulatorSetupOperation)
        if configuration.testing.killSimulatorProcesses {
            operations.append(processKillerOperation)
        }

        testSortingOperation.addDependency(testExtractionOperation)

        distributeTestBundleOperation.addDependency(compileOperation)

        testRunnerOperation.addDependencies([simulatorSetupOperation, distributeTestBundleOperation, testSortingOperation])

        testCollectorOperation.addDependency(testRunnerOperation)

        codeCoverageCollectionOperation.addDependency(testCollectorOperation)
        simulatorTearDownOperation.addDependency(testCollectorOperation)

        cleanupOperation.addDependency(codeCoverageCollectionOperation)

        tearDownOperation.addDependencies([cleanupOperation, simulatorTearDownOperation])

        testSessionResult.device = device
        testSessionResult.destination.username = configuration.resultDestination.node.authentication?.username ?? ""
        testSessionResult.destination.address = configuration.resultDestination.node.address
        testSessionResult.destination.path = "\(configuration.resultDestination.path)/\(timestamp)"
        testSessionResult.date = timestamp
        testSessionResult.git = gitStatus
        testSessionResult.startTime = CFAbsoluteTimeGetCurrent()

        operations.compactMap { $0 as? ThrowingOperation & LoggedOperation }.forEach { [unowned self] op in
            op.didThrow = { opError in
                if (opError as? Error)?.didLogError == false {
                    op.logger.log(exception: opError.localizedDescription)
                }

                print("\n💣 \(op.className.components(separatedBy: ".").last ?? op.className) did throw exception, see session logs for details on what went wrong\n")
                if opError.localizedDescription.count < 2000 {
                    print(opError.localizedDescription)
                }

                self.tearDown(operations: operations, testSessionResult: testSessionResult, error: opError as? Error)
            }
        }

        initialSetupOperation.didEnd = { nodesEnvironment in
            guard let nodesEnvironment = nodesEnvironment,
                  let operations = operations as? [EnvironmentedOperation]
            else {
                return
            }

            for (address, environment) in nodesEnvironment {
                for (k, v) in environment {
                    for operation in operations {
                        var environment = operation.nodesEnvironment[address] ?? [:]
                        environment[k] = v
                        operation.nodesEnvironment[address] = environment
                    }
                }
            }
        }

        validationOperation.didStart = { [unowned self] in
            try? self.eventPlugin.run(event: Event(kind: .start, info: [:]), device: device)
        }
        validationOperation.didThrow = { [unowned self] opError in
            try? self.eventPlugin.run(event: Event(kind: .error, info: ["error": opError.localizedDescription]), device: device)
            self.didFail?(opError)
        }

        testExtractionOperation.didEnd = { testCases in
            testSortingOperation.testCases = testCases
        }

        compileOperation.didStart = { [unowned self] in
            try? self.eventPlugin.run(event: Event(kind: .startCompiling, info: [:]), device: device)
        }
        compileOperation.didEnd = { [unowned self] appInfo in
            try? self.eventPlugin.run(event: Event(kind: .stopCompiling, info: [:]), device: device)
            self.syncQueue.sync {
                testSessionResult.appInfo = appInfo
            }
        }

        switch XcodeProject.SDK(rawValue: sdk)! {
        case .macos:
            testRunnerOperation.testRunners = uniqueNodes.map { (testRunner: $0, node: $0, idle: true) }
        case .ios:
            simulatorSetupOperation.didEnd = { simulators in
                testRunnerOperation.testRunners = simulators.map { (testRunner: $0.0, node: $0.1, idle: true) }
            }
        }

        testSortingOperation.didEnd = { sortedTestCases in
            testRunnerOperation.sortedTestCases = sortedTestCases
        }

        testRunnerOperation.didStart = { [unowned self] in
            try? self.eventPlugin.run(event: Event(kind: .startTesting, info: [:]), device: device)
        }
        testRunnerOperation.didEnd = { [unowned self] testCaseResults in
            testCollectorOperation.testCaseResults = testCaseResults

            try? self.eventPlugin.run(event: Event(kind: .stopTesting, info: [:]), device: device)
        }

        codeCoverageCollectionOperation.didEnd = { [unowned self] coverage in
            self.syncQueue.sync {
                testSessionResult.lineCoveragePercentage = coverage?.data.first?.totals.lines?.percent ?? 0.0
            }
        }

        testCollectorOperation.didEnd = { [unowned self] testCaseResults in
            self.syncQueue.sync {
                testSessionResult.passedTests = testCaseResults.filter { $0.status == .passed }
                testSessionResult.failedTests = testCaseResults.filter { $0.status != .passed }

                let retriedTests = testSessionResult.failedTests.filter { failedTest in testSessionResult.passedTests.contains(where: { passedTest in failedTest.testCaseIdentifier == passedTest.testCaseIdentifier }) }
                testSessionResult.retriedTests = retriedTests

                // Failed test results are those that failed even after retrying
                testSessionResult.failedTests = testCaseResults.filter { testCase in
                    let isRetriedTestCase = testSessionResult.retriedTests.contains { $0.testCaseIdentifier == testCase.testCaseIdentifier }
                    return testCase.status == .failed && !isRetriedTestCase
                }

                // Keep only one failure per testCaseIdentifier
                var uniqueFailedSet = Set<String>()
                let uniqueFailedTests = testSessionResult.failedTests.filter {
                    uniqueFailedSet.update(with: $0.testCaseIdentifier) == nil
                }

                let testCount = Double(testCaseResults.count)
                let failureRate = Double(100 * uniqueFailedTests.count) / testCount
                let retryRate = Double(100 * testSessionResult.retriedTests.count) / testCount

                testSessionResult.failureRate = failureRate
                testSessionResult.retryRate = retryRate
                testSessionResult.totalTestCount = Int(testCount)
                testSessionResult.uniqueFailedTestCount = Int(uniqueFailedTests.count)

                let nodes = Set(testCaseResults.map(\.node))
                for node in nodes {
                    let testCases = testCaseResults.filter { $0.node == node }
                    for xcResultPath in Set(testCases.map(\.xcResultPath)) {
                        testSessionResult.xcResultPath[xcResultPath] = node
                    }
                    guard !testCases.isEmpty else { continue }

                    let executionTime = testCases.reduce(0.0) { $0 + $1.duration }
                    testSessionResult.nodes[node] = .init(executionTime: executionTime, totalTests: testCases.count)
                }
            }
        }

        tearDownOperation.didStart = { [unowned tearDownOperation] in
            tearDownOperation.testSessionResult = self.syncQueue.sync {
                // Make it thread safe
                testSessionResult.copy()
            }
        }

        monitorOperationsExecutionTime(operations, testSessionResult: testSessionResult)

        return operations
    }

    private func tearDown(operations: [RunOperation], testSessionResult: TestSessionResult, error: Error?) {
        cancelOperation(operations)

        let logger = ExecuterLogger(name: "Test", address: "localhost")
        defer { try? logger.dump() }

        let destinationNode = configuration.resultDestination.node
        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)"
        let logsDestinationPath = "\(destinationPath)/sessionLogs"

        let totalExecutionTime = CFAbsoluteTimeGetCurrent() - testSessionResult.startTime
        print("\nℹ️  Total time: \(totalExecutionTime) seconds".bold.yellow)

        // FIXME: - To support macOS we should not required device
        let device = configuration.device ?? Device.defaultInit()

        do {
            try dumpOperationLogs(operations)

            try syncLogs(destinationPath: logsDestinationPath, destination: destinationNode, timestamp: timestamp, logger: logger)

            if let error = error {
                try eventPlugin.run(event: Event(kind: .error, info: ["error": error.localizedDescription]), device: device)
                didFail?(error)
            } else {
                try eventPlugin.run(event: Event(kind: .stop, info: [:]), device: device)
            }
        } catch {
            try? dumpOperationLogs(operations)
            try? eventPlugin.run(event: Event(kind: .error, info: ["error": error.localizedDescription]), device: device)
            didFail?(error)
        }
    }

    private func cancelOperation(_ operations: [Operation]) {
        // To avoid that during cancellation an operation (that wasn't still cancelled) starts because all its dependencies where cancelled
        // we need to cancel from leafs to root
        var completedOperations: Set<Operation> = Set(operations.filter { $0.isCancelled || $0.isFinished })

        while true {
            for operation in operations {
                guard !completedOperations.contains(operation) else { continue }

                let dependingOperations = operations.filter { $0.dependencies.contains(operation) }

                if dependingOperations.allSatisfy(\.isCancelled) {
                    operation.cancel()
                    completedOperations.insert(operation)
                    break
                }
            }
            guard completedOperations.count != operations.count else { break }
        }
    }

    private func monitorOperationsExecutionTime(_ operations: [Operation], testSessionResult: TestSessionResult) {
        operations.forEach { op in
            let observer = op.observe(\Operation.isFinished) { [unowned self] op, _ in
                guard let op = op as? BenchmarkedOperation else { return }

                let name = "\(type(of: op))"

                self.syncQueue.sync {
                    testSessionResult.operationStartInterval[name] = op.startTimeInterval
                    testSessionResult.operationEndInterval[name] = op.endTimeInterval

                    testSessionResult.operationPoolStartInterval[name] = op.poolStartTimeInterval()
                    testSessionResult.operationPoolEndInterval[name] = op.poolEndTimeInterval()
                }
            }

            self.observers.append(observer)
        }
    }
}

private extension Test {
    static func currentTimestamp() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"

        return dateFormatter.string(from: Date())
    }

    func dumpOperationLogs(_ operations: [LoggedOperation]) throws {
        let loggerCoordinator = LoggerCoordinator(operations: operations)

        try loggerCoordinator.dump()
    }

    func syncLogs(destinationPath: String, destination: Node, timestamp _: String, logger: ExecuterLogger) throws {
        let logPath = "\(Path.logs.rawValue)/*.html"

        let executer = LocalExecuter(logger: logger)
        try executer.rsync(sourcePath: logPath, destinationPath: destinationPath, on: destination)
        try logger.dump()
    }

    func localProject(baseUrl: URL, path: String) throws -> XcodeProject {
        if path.hasPrefix("/") {
            return try XcodeProject(url: URL(filePath: path))
        } else {
            return try XcodeProject(url: baseUrl.appendingPathComponent(path))
        }
    }
}

private extension TestSessionResult {
    func copy() -> TestSessionResult? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(TestSessionResult.self, from: data)
    }
}

private extension String {
    func pathExpandingTilde() -> String {
        replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
