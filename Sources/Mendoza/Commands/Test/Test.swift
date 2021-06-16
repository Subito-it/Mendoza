//
//  Test.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

class Test {
    var didFail: ((Swift.Error) -> Void)?

    // swiftlint:disable:next large_tuple
    private let userOptions: (configuration: Configuration, device: Device, runHeadless: Bool, filePatterns: FilePatterns, testTimeoutSeconds: Int, failingTestsRetryCount: Int, codeCoveragePathEquivalence: String?, dispatchOnLocalHost: Bool, verbose: Bool)
    private let plugin: (data: String?, debug: Bool)
    private let eventPlugin: EventPlugin
    private let pluginUrl: URL
    private let syncQueue = DispatchQueue(label: String(describing: Test.self))
    private let timestamp: String
    private var observers = [NSKeyValueObservation]()

    init(configurationUrl: URL, device: Device, runHeadless: Bool, filePatterns: FilePatterns, testTimeoutSeconds: Int, failingTestsRetryCount: Int, codeCoveragePathEquivalence: String?, dispatchOnLocalHost: Bool, pluginData: String?, debugPlugins: Bool, verbose: Bool) throws {
        plugin = (data: pluginData, debug: debugPlugins)

        let configurationData = try Data(contentsOf: configurationUrl)
        var configuration = try JSONDecoder().decode(Configuration.self, from: configurationData)

        if dispatchOnLocalHost, !configuration.nodes.contains(where: { AddressType(node: $0) == .local }) { // add localhost
            let updatedNodes = configuration.nodes + [Node.localhost()]
            let updatedConfiguration = Configuration(projectPath: configuration.projectPath, workspacePath: configuration.workspacePath, buildBundleIdentifier: configuration.buildBundleIdentifier, testBundleIdentifier: configuration.testBundleIdentifier, scheme: configuration.scheme, buildConfiguration: configuration.buildConfiguration, storeAppleIdCredentials: configuration.storeAppleIdCredentials, resultDestination: configuration.resultDestination, nodes: updatedNodes, compilation: configuration.compilation, sdk: configuration.sdk)
            configuration = updatedConfiguration
        }

        userOptions = (configuration: configuration, device: device, runHeadless: runHeadless, filePatterns: filePatterns, testTimeoutSeconds: testTimeoutSeconds, failingTestsRetryCount: failingTestsRetryCount, codeCoveragePathEquivalence: codeCoveragePathEquivalence, dispatchOnLocalHost: dispatchOnLocalHost, verbose: verbose)

        pluginUrl = configurationUrl.deletingLastPathComponent()
        eventPlugin = EventPlugin(baseUrl: pluginUrl, plugin: plugin)

        timestamp = Test.currentTimestamp()
    }

    func run() throws {
        guard let sdk = XcodeProject.SDK(rawValue: userOptions.configuration.sdk) else {
            throw Error("Invalid sdk \(userOptions.configuration.sdk)")
        }

        switch sdk {
        case .ios:
            if userOptions.device.name.isEmpty, userOptions.device.name.isEmpty {
                throw Error("Missing required arguments `--device_name=name, --device_runtime=version`".red)
            } else if userOptions.device.name.isEmpty {
                throw Error("Missing required arguments `--device_name=name`".red)
            } else if userOptions.device.runtime.isEmpty {
                throw Error("Missing required arguments `--device_runtime=version`".red)
            }
        case .macos:
            break
        }
        
        if let codeCoveragePathEquivalence = userOptions.codeCoveragePathEquivalence {
            if codeCoveragePathEquivalence.components(separatedBy: ",").count != 2 {
                throw Error("Invalid format for --llvm_cov_equivalence_path parameter, expecting --llvm_cov_equivalence_path=<from>,<to>".red)
            }
        }

        print("ℹ️  Dispatching on".magenta.bold)
        let nodes = Array(Set(userOptions.configuration.nodes.map(\.address) + (userOptions.dispatchOnLocalHost ? ["localhost"] : []))).sorted()
        print(nodes.joined(separator: "\n").magenta)

        let git = Git(executer: LocalExecuter())
        let gitStatus = try git.status()

        let queue = OperationQueue()

        let testSessionResult = TestSessionResult()
        let arguments: [String?] = [userOptions.device.name,
                                    userOptions.device.runtime,
                                    userOptions.filePatterns.include.sorted().joined(separator: ","),
                                    userOptions.filePatterns.exclude.sorted().joined(separator: ","),
                                    plugin.data]
        
        testSessionResult.launchArguments = arguments.compactMap { $0 }.joined(separator: " ")
        
        let operations = try makeOperations(gitStatus: gitStatus, testSessionResult: testSessionResult, sdk: sdk)

        queue.addOperations(operations, waitUntilFinished: true)

        tearDown(operations: operations, testSessionResult: testSessionResult, error: nil)
    }

    private func makeOperations(gitStatus: GitStatus, testSessionResult: TestSessionResult, sdk: XcodeProject.SDK) throws -> [Operation & LoggedOperation] {
        typealias RunOperation = Operation & LoggedOperation

        let configuration = userOptions.configuration
        let device = userOptions.device
        let filePatterns = userOptions.filePatterns
        let codeCoveragePathEquivalence = userOptions.codeCoveragePathEquivalence

        let gitBaseUrl = gitStatus.url
        let project = try localProject(baseUrl: gitBaseUrl, path: configuration.projectPath)

        let uniqueNodes = configuration.nodes.unique()
        let targets = try project.getTargetsInScheme(configuration.scheme)
        let testTargetSourceFiles = try project.testTargetSourceFilePaths(scheme: configuration.scheme)

        let preCompilationPlugin = PreCompilationPlugin(baseUrl: pluginUrl, plugin: plugin)
        let postCompilationPlugin = PostCompilationPlugin(baseUrl: pluginUrl, plugin: plugin)
        let testExtractionPlugin = TestExtractionPlugin(baseUrl: pluginUrl, plugin: plugin)
        let testSortingPlugin = TestSortingPlugin(baseUrl: pluginUrl, plugin: plugin)
        let tearDownPlugin = TearDownPlugin(baseUrl: pluginUrl, plugin: plugin)

        let initialSetupOperation = InitialSetupOperation(nodes: uniqueNodes)
        let validationOperation = ValidationOperation(configuration: configuration)
        let macOsValidationOperation = MacOsValidationOperation(configuration: configuration)
        let localSetupOperation = LocalSetupOperation()
        let wakeupOperation = WakeupOperation(nodes: uniqueNodes)
        let remoteSetupOperation = RemoteSetupOperation(nodes: uniqueNodes)
        let compileOperation = CompileOperation(configuration: configuration, git: gitStatus, baseUrl: gitBaseUrl, project: project, scheme: configuration.scheme, preCompilationPlugin: preCompilationPlugin, postCompilationPlugin: postCompilationPlugin, sdk: sdk)
        let testExtractionOperation = TestExtractionOperation(configuration: configuration, baseUrl: gitBaseUrl, testTargetSourceFiles: testTargetSourceFiles, filePatterns: filePatterns, device: device, plugin: testExtractionPlugin)
        let testSortingOperation = TestSortingOperation(device: device, plugin: testSortingPlugin, verbose: userOptions.verbose)
        let simulatorSetupOperation = SimulatorSetupOperation(configuration: configuration, nodes: uniqueNodes, device: device, runHeadless: userOptions.runHeadless, verbose: userOptions.verbose)
        let distributeTestBundleOperation = DistributeTestBundleOperation(nodes: uniqueNodes)
        let testRunnerOperation = TestRunnerOperation(configuration: configuration, buildTarget: targets.build.name, testTarget: targets.test.name, sdk: sdk, failingTestsRetryCount: userOptions.failingTestsRetryCount, testTimeoutSeconds: userOptions.testTimeoutSeconds, verbose: userOptions.verbose)
        let testCollectorOperation = TestCollectorOperation(configuration: configuration, timestamp: timestamp, buildTarget: targets.build.name, testTarget: targets.test.name)

        let codeCoverageCollectionOperation = CodeCoverageCollectionOperation(configuration: configuration, pathEquivalence: codeCoveragePathEquivalence, baseUrl: gitBaseUrl, timestamp: timestamp)
        let testTearDownOperation = TestTearDownOperation(configuration: configuration, git: gitStatus, timestamp: timestamp)
        let cleanupOperation = CleanupOperation(configuration: configuration, timestamp: timestamp)
        let simulatorTearDownOperation = SimulatorTearDownOperation(configuration: configuration, nodes: uniqueNodes, verbose: userOptions.verbose)
        let tearDownOperation = TearDownOperation(configuration: configuration, plugin: tearDownPlugin)

        let operations: [RunOperation] =
            [initialSetupOperation,
             compileOperation,
             validationOperation,
             macOsValidationOperation,
             localSetupOperation,
             remoteSetupOperation,
             wakeupOperation,
             testExtractionOperation,
             testSortingOperation,
             simulatorSetupOperation,
             distributeTestBundleOperation,
             testRunnerOperation,
             testCollectorOperation,
             codeCoverageCollectionOperation,
             testTearDownOperation,
             simulatorTearDownOperation,
             cleanupOperation,
             tearDownOperation]

        switch sdk {
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

        wakeupOperation.addDependencies([localSetupOperation, remoteSetupOperation])

        testExtractionOperation.addDependency(localSetupOperation)

        simulatorSetupOperation.addDependency(wakeupOperation)

        testSortingOperation.addDependency(testExtractionOperation)

        distributeTestBundleOperation.addDependency(compileOperation)

        testRunnerOperation.addDependencies([simulatorSetupOperation, distributeTestBundleOperation, testSortingOperation])

        testCollectorOperation.addDependency(testRunnerOperation)

        codeCoverageCollectionOperation.addDependency(testCollectorOperation)
        testTearDownOperation.addDependency(testCollectorOperation)
        simulatorTearDownOperation.addDependency(testCollectorOperation)

        cleanupOperation.addDependencies([codeCoverageCollectionOperation, testTearDownOperation])

        tearDownOperation.addDependencies([cleanupOperation, simulatorTearDownOperation])

        testSessionResult.device = device
        testSessionResult.destination.username = configuration.resultDestination.node.authentication?.username ?? ""
        testSessionResult.destination.address = configuration.resultDestination.node.address
        testSessionResult.destination.path = "\(configuration.resultDestination.path)/\(timestamp)"
        testSessionResult.date = timestamp
        testSessionResult.git = gitStatus
        testSessionResult.startTime = CFAbsoluteTimeGetCurrent()

        operations.compactMap { $0 as? Throwing & LoggedOperation }.forEach { [unowned self] op in
            op.didThrow = { opError in
                if (opError as? Error)?.didLogError == false {
                    op.logger.log(exception: opError.localizedDescription)
                }

                print("\n💥 \(op.className.components(separatedBy: ".").last ?? op.className) did throw exception, see session logs for details on what went wrong\n")
                if opError.localizedDescription.count < 2000 {
                    print(opError.localizedDescription)
                }

                self.tearDown(operations: operations, testSessionResult: testSessionResult, error: opError as? Error)
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

        switch sdk {
        case .macos:
            testRunnerOperation.testRunners = uniqueNodes.map { (testRunner: $0, node: $0) }
        case .ios:
            simulatorSetupOperation.didEnd = { simulators in
                testRunnerOperation.testRunners = simulators.map { (testRunner: $0.0, node: $0.1) }
            }
        }

        testSortingOperation.didEnd = { sortedTestCases in
            testRunnerOperation.sortedTestCases = sortedTestCases
        }

        testRunnerOperation.didStart = { [unowned self] in
            try? self.eventPlugin.run(event: Event(kind: .startTesting, info: [:]), device: device)
        }
        testRunnerOperation.didEnd = { [unowned self] testCaseResults in
            self.syncQueue.sync {
                testSessionResult.passedTests = testCaseResults.filter { $0.status == .passed }
                testSessionResult.failedTests = testCaseResults.filter { $0.status != .passed }
                
                let retriedTests = testSessionResult.failedTests.filter { failedTest in testSessionResult.passedTests.contains(where: { passedTest in failedTest.testCaseIdentifier == passedTest.testCaseIdentifier } )}
                testSessionResult.retriedTests = retriedTests

                // Failed test results are those that failed even after retrying
                testSessionResult.failedTests = testCaseResults.filter { testCase in
                    let isRetriedTestCase = testSessionResult.retriedTests.contains { $0.testCaseIdentifier == testCase.testCaseIdentifier }
                    return testCase.status == .failed && !isRetriedTestCase
                }
                
                // Keep only one failure per testCaseIdentifier
                var uniqueFailedSessions = Set<String>()
                testSessionResult.failedTests = testSessionResult.failedTests.filter {
                    uniqueFailedSessions.update(with: $0.testCaseIdentifier) == nil
                }
                
                let testCount = Double(testCaseResults.count)
                let failureRate = Double(100 * testSessionResult.failedTests.count) / testCount
                let retryRate = Double(100 * testSessionResult.retriedTests.count) / testCount
                
                testSessionResult.failureRate = failureRate
                testSessionResult.retryRate = retryRate
                testSessionResult.totalTestCount = Int(testCount)

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

            testCollectorOperation.testCaseResults = testCaseResults
            testTearDownOperation.testCaseResults = testCaseResults
            try? self.eventPlugin.run(event: Event(kind: .stopTesting, info: [:]), device: device)
        }
        
        codeCoverageCollectionOperation.didEnd = { [unowned self] coverage in
            self.syncQueue.sync {
                testSessionResult.lineCoveragePercentage = coverage?.data.first?.totals.lines?.percent ?? 0.0
            }
        }

        tearDownOperation.didStart = { [unowned tearDownOperation] in
            tearDownOperation.testSessionResult = testSessionResult
        }

        monitorOperationsExecutionTime(operations, testSessionResult: testSessionResult)

        return operations
    }

    private func tearDown(operations: [Operation & LoggedOperation], testSessionResult: TestSessionResult, error: Error?) {
        cancelOperation(operations)

        let logger = ExecuterLogger(name: "Test", address: "localhost")
        defer { try? logger.dump() }

        let destinationNode = userOptions.configuration.resultDestination.node
        let destinationPath = "\(userOptions.configuration.resultDestination.path)/\(timestamp)"
        let logsDestinationPath = "\(destinationPath)/sessionLogs"

        let totalExecutionTime = CFAbsoluteTimeGetCurrent() - testSessionResult.startTime
        print("\nℹ️  Total time: \(totalExecutionTime) seconds".bold.yellow)

        do {
            try writeTestSuiteResult(syncQueue.sync { testSessionResult }, destinationPath: destinationPath, destination: destinationNode, timestamp: timestamp, logger: logger)

            try dumpOperationLogs(operations)

            try syncLogs(destinationPath: logsDestinationPath, destination: destinationNode, timestamp: timestamp, logger: logger)

            if let error = error {
                try eventPlugin.run(event: Event(kind: .error, info: ["error": error.localizedDescription]), device: userOptions.device)
                didFail?(error)
            } else {
                try eventPlugin.run(event: Event(kind: .stop, info: [:]), device: userOptions.device)
            }
        } catch {
            try? dumpOperationLogs(operations)
            try? eventPlugin.run(event: Event(kind: .error, info: ["error": error.localizedDescription]), device: userOptions.device)
            didFail?(error)
        }
    }

    private func cancelOperation(_ operations: [Operation & LoggedOperation]) {
        // To avoid that during cancellation an operation (that wasn't still cancelled) starts because all its dependencies where cancelled
        // we need to cancel from leafs to root
        var completedOperations: Set<Operation> = Set(operations.filter { $0.isCancelled || $0.isFinished })

        while true {
            for operation in operations {
                guard !completedOperations.contains(operation) else { continue }

                let dependingOperations = operations.filter { $0.dependencies.contains(operation) }

                if dependingOperations.allSatisfy({ $0.isCancelled }) {
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
            let observer = op.observe(\Operation.isExecuting) { [unowned self] op, _ in
                let name = "\(type(of: op))"

                self.syncQueue.sync {
                    if op.isFinished {
                        guard let start = testSessionResult.operationExecutionTime[name] else { return }
                        testSessionResult.operationExecutionTime[name] = CFAbsoluteTimeGetCurrent() - start
                    } else {
                        testSessionResult.operationExecutionTime[name] = CFAbsoluteTimeGetCurrent()
                    }
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

    func dumpOperationLogs(_ operations: [Operation & LoggedOperation]) throws {
        let loggerCoordinator = LoggerCoordinator(operations: operations)

        try loggerCoordinator.dump()
    }

    func writeTestSuiteResult(_ testSessionResult: TestSessionResult, destinationPath: String, destination: Node, timestamp _: String, logger: ExecuterLogger) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(testSessionResult)

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: tempUrl)

        let executer = try destination.makeExecuter(logger: logger)
        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try executer.upload(localUrl: tempUrl, remotePath: "\(destinationPath)/\(Environment.suiteResultFilename)")
        try logger.dump()
    }

    func syncLogs(destinationPath: String, destination: Node, timestamp _: String, logger: ExecuterLogger) throws {
        let logPath = "\(Path.logs.rawValue)/*.html"

        let executer = LocalExecuter(logger: logger)
        try executer.rsync(sourcePath: logPath, destinationPath: destinationPath, on: destination)
        try logger.dump()
    }

    func localProject(baseUrl: URL, path: String) throws -> XcodeProject {
        try XcodeProject(url: baseUrl.appendingPathComponent(path))
    }
}
