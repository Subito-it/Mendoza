//
//  Test.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

class Test {
    var didFail: ((Swift.Error) -> Void)?
    
    private let userOptions: (configuration: Configuration, device: Device, runHeadless: Bool, filePatterns: FilePatterns, testTimeoutSeconds: Int, failingTestsRetryCount: Int, dispatchOnLocalHost: Bool, verbose: Bool)
    private let plugin: (data: String?, debug: Bool)
    private let eventPlugin: EventPlugin
    private let pluginUrl: URL
    private let syncQueue = DispatchQueue(label: String(describing: Test.self))
    private let timestamp: String
    private var observers = [NSKeyValueObservation]()
    
    init(configurationUrl: URL, device: Device, runHeadless: Bool, filePatterns: FilePatterns, testTimeoutSeconds: Int, failingTestsRetryCount: Int, dispatchOnLocalHost: Bool, pluginData: String?, debugPlugins: Bool, verbose: Bool) throws {
        self.plugin = (data: pluginData, debug: debugPlugins)
        
        let configurationData = try Data(contentsOf: configurationUrl)
        var configuration = try JSONDecoder().decode(Configuration.self, from: configurationData)
        
        if dispatchOnLocalHost && configuration.nodes.first(where: { AddressType(node: $0) == .local }) == nil { // add localhost
            let updatedNodes = configuration.nodes + [Node.localhost()]
            let updatedConfiguration = Configuration(projectPath: configuration.projectPath, workspacePath: configuration.workspacePath, buildBundleIdentifier: configuration.buildBundleIdentifier, testBundleIdentifier: configuration.testBundleIdentifier, scheme: configuration.scheme, buildConfiguration: configuration.buildConfiguration, storeAppleIdCredentials: configuration.storeAppleIdCredentials, resultDestination: configuration.resultDestination, nodes: updatedNodes, compilation: configuration.compilation, sdk: configuration.sdk)
            configuration = updatedConfiguration
        }
        
        self.userOptions = (configuration: configuration, device: device, runHeadless: runHeadless, filePatterns: filePatterns, testTimeoutSeconds: testTimeoutSeconds, failingTestsRetryCount: failingTestsRetryCount, dispatchOnLocalHost: dispatchOnLocalHost, verbose: verbose)
        
        self.pluginUrl = configurationUrl.deletingLastPathComponent()
        self.eventPlugin = EventPlugin(baseUrl: pluginUrl, plugin: plugin)
        
        self.timestamp = Test.currentTimestamp()
    }
    
    func run() throws -> Void {
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
        
        print("ℹ️  Dispatching on".magenta.bold)
        let nodes = Array(Set(userOptions.configuration.nodes.map { $0.address } + (userOptions.dispatchOnLocalHost ? ["localhost"] : []))).sorted()
        print(nodes.joined(separator: "\n").magenta)
        
        let git = Git(executer: LocalExecuter())
        let gitStatus = try git.status()
        #if !DEBUG
            try git.pull()
        #endif
        
        let queue = OperationQueue()
        
        let testSessionResult = TestSessionResult()

        let operations = try makeOperations(gitStatus: gitStatus, testSessionResult: testSessionResult, sdk: sdk)
        
        queue.addOperations(operations, waitUntilFinished: true)
        
        tearDown(operations: operations, testSessionResult: testSessionResult, error: nil)
    }
    
    private func makeOperations(gitStatus: GitStatus, testSessionResult: TestSessionResult, sdk: XcodeProject.SDK) throws -> [Operation & LoggedOperation] {
        typealias RunOperation = Operation & LoggedOperation
        
        let configuration = userOptions.configuration
        let device = userOptions.device
        let filePatterns = userOptions.filePatterns
        
        let gitBaseUrl = gitStatus.url
        let project = try localProject(baseUrl: gitBaseUrl, path: configuration.projectPath)
        
        let uniqueNodes = configuration.nodes.unique()
        let targets = try project.getTargetsInScheme(configuration.scheme)
        let testTargetSourceFiles = try project.testTargetSourceFilePaths(scheme: configuration.scheme)
        
        let preCompilationPlugin = PreCompilationPlugin(baseUrl: pluginUrl, plugin: plugin)
        let postCompilationPlugin = PostCompilationPlugin(baseUrl: pluginUrl, plugin: plugin)
        let testExtractionPlugin = TestExtractionPlugin(baseUrl: pluginUrl, plugin: plugin)
        let testDistributionPlugin = TestDistributionPlugin(baseUrl: pluginUrl, plugin: plugin)
        let tearDownPlugin = TearDownPlugin(baseUrl: pluginUrl, plugin: plugin)
        
        let validationOperation = ValidationOperation(configuration: configuration)
        let macOsValidationOperation = MacOsValidationOperation(configuration: configuration)
        let localSetupOperation = LocalSetupOperation()
        let wakeupOperation = WakeupOperation(nodes: uniqueNodes)
        let setupOperation = SetupOperation(nodes: uniqueNodes)
        let compileOperation = CompileOperation(configuration: configuration, baseUrl: gitBaseUrl, project: project, scheme: configuration.scheme, preCompilationPlugin: preCompilationPlugin, postCompilationPlugin: postCompilationPlugin, sdk: sdk)
        let testExtractionOperation = TestExtractionOperation(configuration: configuration, baseUrl: gitBaseUrl, testTargetSourceFiles: testTargetSourceFiles, filePatterns: filePatterns, device: device, plugin: testExtractionPlugin)
        let testDistributionOperation = TestDistributionOperation(device: device, plugin: testDistributionPlugin, verbose: userOptions.verbose)
        let simulatorSetupOperation = SimulatorSetupOperation(configuration: configuration, nodes: uniqueNodes, device: device, runHeadless: userOptions.runHeadless, verbose: userOptions.verbose)
        let simulatorBootOperation = SimulatorBootOperation(verbose: userOptions.verbose)
        let simulatorWakeupOperation = SimulatorWakeupOperation(nodes: uniqueNodes, runHeadless: userOptions.runHeadless, verbose: userOptions.verbose)
        let distributeTestBundleOperation = DistributeTestBundleOperation(nodes: uniqueNodes)
        let testRunnerOperation = TestRunnerOperation(configuration: configuration, buildTarget: targets.build.name, testTarget: targets.test.name, sdk: sdk, testTimeoutSeconds: userOptions.testTimeoutSeconds, verbose: userOptions.verbose)
        
        var retryTestDistributionOperations = [TestDistributionOperation]()
        var retryTestRunnerOperations = [TestRunnerOperation]()
        for _ in 0..<userOptions.failingTestsRetryCount {
            retryTestDistributionOperations.append(.init(device: device, plugin: testDistributionPlugin, verbose: userOptions.verbose))
            retryTestRunnerOperations.append(.init(configuration: configuration, buildTarget: targets.build.name, testTarget: targets.test.name, sdk: sdk, testTimeoutSeconds: userOptions.testTimeoutSeconds, verbose: userOptions.verbose))
        }
        let testCollectorOperation = TestCollectorOperation(configuration: configuration, timestamp: timestamp, buildTarget: targets.build.name, testTarget: targets.test.name)
        let testTearDownOperation = TestTearDownOperation(configuration: configuration, git: gitStatus, timestamp: timestamp)
        let cleanupOperation = CleanupOperation(configuration: configuration, timestamp: timestamp)
        let simulatorTearDownOperation = SimulatorTearDownOperation(configuration: configuration, nodes: uniqueNodes, verbose: userOptions.verbose)
        let tearDownOperation = TearDownOperation(configuration: configuration, plugin: tearDownPlugin)
        
        let operations: [RunOperation] =
            [validationOperation,
             macOsValidationOperation,
             localSetupOperation,
             setupOperation,
             wakeupOperation,
             compileOperation,
             testExtractionOperation,
             testDistributionOperation,
             simulatorSetupOperation,
             simulatorBootOperation,
             simulatorWakeupOperation,
             distributeTestBundleOperation,
             testRunnerOperation,
             testCollectorOperation,
             testTearDownOperation,
             simulatorTearDownOperation,
             cleanupOperation,
             tearDownOperation] + retryTestDistributionOperations + retryTestRunnerOperations
        
        switch sdk {
        case .ios:
            macOsValidationOperation.cancel()
        case .macos:
            simulatorTearDownOperation.cancel()
            simulatorWakeupOperation.cancel()
            simulatorBootOperation.cancel()
            simulatorSetupOperation.cancel()
        }

        wakeupOperation.addDependency(validationOperation)
        localSetupOperation.addDependencies([validationOperation, macOsValidationOperation])
        
        setupOperation.addDependency(localSetupOperation)
        testExtractionOperation.addDependency(localSetupOperation)
        
        compileOperation.addDependency(setupOperation)
        simulatorSetupOperation.addDependencies([setupOperation, wakeupOperation])
        
        testDistributionOperation.addDependency(testExtractionOperation)
        testDistributionOperation.addDependency(simulatorSetupOperation)
        
        simulatorBootOperation.addDependency(simulatorSetupOperation)
        simulatorWakeupOperation.addDependency(simulatorBootOperation)
        
        distributeTestBundleOperation.addDependency(compileOperation)
        
        testRunnerOperation.addDependencies([simulatorWakeupOperation, distributeTestBundleOperation, testDistributionOperation])
        
        var lastTestRunnerOperation = testRunnerOperation
        for index in 0..<userOptions.failingTestsRetryCount {
            retryTestDistributionOperations[index].addDependency(lastTestRunnerOperation)
            retryTestRunnerOperations[index].addDependency(retryTestDistributionOperations[index])
            
            lastTestRunnerOperation = retryTestRunnerOperations[index]
        }
        
        testCollectorOperation.addDependency(lastTestRunnerOperation)
        
        testTearDownOperation.addDependency(testCollectorOperation)
        simulatorTearDownOperation.addDependency(testCollectorOperation)
        
        cleanupOperation.addDependency(testTearDownOperation)
        
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
            testDistributionOperation.testCases = testCases
        }
        
        compileOperation.didStart = { [unowned self] in
            try? self.eventPlugin.run(event: Event(kind: .startCompiling, info: [:]), device: device)
        }
        compileOperation.didEnd = { [unowned self] _ in
            try? self.eventPlugin.run(event: Event(kind: .stopCompiling, info: [:]), device: device)
        }
        
        switch sdk {
        case .macos:
            testDistributionOperation.testRunnersCount = uniqueNodes.count
            testRunnerOperation.testRunners = uniqueNodes.map { (testRunner: $0, node: $0) }
            
            retryTestDistributionOperations.forEach { $0.testRunnersCount = testDistributionOperation.testRunnersCount }
            retryTestRunnerOperations.forEach { $0.testRunners = testRunnerOperation.testRunners }
        case .ios:
            simulatorSetupOperation.didEnd = { simulators in
                simulatorBootOperation.simulators = simulators
                
                testDistributionOperation.testRunnersCount = simulators.count
                testRunnerOperation.testRunners = simulators.map { (testRunner: $0.0, node: $0.1) }
                
                retryTestDistributionOperations.forEach { $0.testRunnersCount = testDistributionOperation.testRunnersCount }
                retryTestRunnerOperations.forEach { $0.testRunners = testRunnerOperation.testRunners }
            }
        }
        
        testDistributionOperation.didEnd = { distributedTestCases in
            testRunnerOperation.distributedTestCases = distributedTestCases
        }
        
        testRunnerOperation.didStart = { [unowned self] in
            try? self.eventPlugin.run(event: Event(kind: .startTesting, info: [:]), device: device)
        }
        testRunnerOperation.didEnd = { [unowned self] testCaseResults in
            self.syncQueue.sync {
                testSessionResult.passedTests = testCaseResults.filter { $0.status == .passed }
                
                // Failed test results are those that failed even after retrying
                testSessionResult.failedTests = testCaseResults.filter { result in
                    let passedOnRepeat = testSessionResult.passedTests.contains { successResult in
                        return result.testCaseIdentifier == successResult.testCaseIdentifier
                    }
                    
                    return result.status == .failed && passedOnRepeat == false
                }
                // We should keep only one failure per test.suite + test.name
                var uniqueFailedSessions = Set<String>()
                testSessionResult.failedTests = testSessionResult.failedTests.filter {
                    uniqueFailedSessions.update(with: $0.testCaseIdentifier) == nil
                }

                let nodes = Set(testCaseResults.map { $0.node })
                for node in nodes {
                    let testCases = testCaseResults.filter { $0.node == node }
                    for xcResultPath in Set(testCases.map { $0.xcResultPath }) {
                        testSessionResult.xcResultPath[xcResultPath] = node
                    }
                    guard testCases.count > 0 else { continue }
                    
                    let executionTime = testCases.reduce(0.0, { $0 + $1.duration })
                    testSessionResult.nodes[node] = .init(executionTime: executionTime, totalTests: testCases.count)
                }
            }
            
            testCollectorOperation.testCaseResults = testCaseResults
            testTearDownOperation.testCaseResults = testCaseResults
            try? self.eventPlugin.run(event: Event(kind: .stopTesting, info: [:]), device: device)
        }
                
        if userOptions.failingTestsRetryCount > 0 {
            retryTestRunnerOperations.last?.didEnd = testRunnerOperation.didEnd
            retryTestRunnerOperations.insert(testRunnerOperation, at: 0)
            
            for index in 0..<retryTestRunnerOperations.count {
                retryTestRunnerOperations[index].didStart = { [unowned self] in                    
                    try? self.eventPlugin.run(event: Event(kind: .startTesting, info: ["retry_indx": "\(index)"]), device: device)
                }
            }
            for index in 0..<retryTestRunnerOperations.count - 1 {
                retryTestRunnerOperations[index].didEnd = { [unowned self] testCaseResults in
                    let failingGroups = Dictionary(grouping: testCaseResults, by: { "\($0.suite)/\($0.name)" }).values.filter { $0.allSatisfy { $0.status == .failed }}
                    
                    let failingTestCases = failingGroups.compactMap { $0.first }.map { TestCase(name: $0.name, suite: $0.suite) }
                    retryTestDistributionOperations[index].testCases = failingTestCases
                    
                    for index2 in index + 1..<retryTestRunnerOperations.count {
                        retryTestRunnerOperations[index2].currentResult = testCaseResults
                    }
                    
                    let nodes = Set(testCaseResults.map { $0.node })
                    for node in nodes {
                        let testCases = testCaseResults.filter { $0.node == node }
                        for xcResultPath in Set(testCases.map { $0.xcResultPath }) {
                            testSessionResult.xcResultPath[xcResultPath] = node
                        }
                        
                        let executionTime = testCases.reduce(0.0, { $0 + $1.duration })
                        testSessionResult.nodes["\(node)-r\(index)"] = .init(executionTime: executionTime, totalTests: testCases.count)
                    }
                    
                    try? self.eventPlugin.run(event: Event(kind: .stopTesting, info: ["retry_indx": "\(index)"]), device: device)
                }
            }
            assert(retryTestDistributionOperations.count == retryTestRunnerOperations.count - 1, "💣 Wrong sizing")
            for index in 0..<retryTestDistributionOperations.count {
                retryTestDistributionOperations[index].didEnd = { distributedTestCases in
                    retryTestRunnerOperations[index + 1].distributedTestCases = distributedTestCases
                }
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
            try writeTestSuiteResult(syncQueue.sync { return testSessionResult }, destinationPath: destinationPath, destination: destinationNode, timestamp: timestamp, logger: logger)
            
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
    
    func writeTestSuiteResult(_ testSessionResult: TestSessionResult, destinationPath: String, destination: Node, timestamp: String, logger: ExecuterLogger) throws {
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
    
    func syncLogs(destinationPath: String, destination: Node, timestamp: String, logger: ExecuterLogger) throws {
        let logPath = "\(Path.logs.rawValue)/*.html"
        
        let executer = LocalExecuter(logger: logger)
        try executer.rsync(sourcePath: logPath, destinationPath: destinationPath, on: destination)
        try logger.dump()
    }
    
    func localProject(baseUrl: URL, path: String) throws -> XcodeProject {
        return try XcodeProject(url: baseUrl.appendingPathComponent(path))
    }
}
