//
//  Test.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

class Test {
    var didFail: ((Swift.Error) -> Void)?
    
    private let userOptions: (configuration: Configuration, device: Device, filePatterns: FilePatterns, timeoutMinutes: Int, dispatchOnLocalHost: Bool)
    private let plugin: (data: String?, debug: Bool)
    private let eventPlugin: EventPlugin
    private let pluginUrl: URL
    private let syncQueue = DispatchQueue(label: String(describing: Test.self))
    private let timestamp: String
    private var observers = [NSKeyValueObservation]()
    
    init(configurationUrl: URL, device: Device, filePatterns: FilePatterns, timeoutMinutes: Int, dispatchOnLocalHost: Bool, pluginData: String?, debugPlugins: Bool) throws {
        self.plugin = (data: pluginData, debug: debugPlugins)
        
        let configurationData = try Data(contentsOf: configurationUrl)
        var configuration = try JSONDecoder().decode(Configuration.self, from: configurationData)
        
        if dispatchOnLocalHost && configuration.nodes.first(where: { AddressType(node: $0) == .local }) == nil { // add localhost
            let updatedNodes = configuration.nodes + [Node.localhost()]
            let updatedConfiguration = Configuration(projectPath: configuration.projectPath, workspacePath: configuration.workspacePath, buildBundleIdentifier: configuration.buildBundleIdentifier, testBundleIdentifier: configuration.testBundleIdentifier, scheme: configuration.scheme, buildConfiguration: configuration.buildConfiguration, storeAppleIdCredentials: configuration.storeAppleIdCredentials, resultDestination: configuration.resultDestination, nodes: updatedNodes, compilation: configuration.compilation)
            configuration = updatedConfiguration
        }
        
        self.userOptions = (configuration: configuration, device: device, filePatterns: filePatterns, timeoutMinutes: timeoutMinutes, dispatchOnLocalHost: dispatchOnLocalHost)
        
        self.pluginUrl = configurationUrl.deletingLastPathComponent()
        self.eventPlugin = EventPlugin(baseUrl: pluginUrl, plugin: plugin)
        
        self.timestamp = Test.currentTimestamp()
    }
    
    func run() throws -> Void {
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

        let operations = try makeOperations(gitStatus: gitStatus, testSessionResult: testSessionResult)
        
        queue.addOperations(operations, waitUntilFinished: true)
        
        tearDown(operations: operations, testSessionResult: testSessionResult, error: nil)
    }
    
    private func makeOperations(gitStatus: GitStatus, testSessionResult: TestSessionResult) throws -> [Operation & LoggedOperation] {
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
        let localSetupOperation = LocalSetupOperation()
        let wakeupOperation = WakeupOperation(nodes: uniqueNodes)
        let setupOperation = SetupOperation(nodes: uniqueNodes)
        let compileOperation = CompileOperation(configuration: configuration, baseUrl: gitBaseUrl, project: project, scheme: configuration.scheme, preCompilationPlugin: preCompilationPlugin, postCompilationPlugin: postCompilationPlugin)
        let testExtractionOperation = TestExtractionOperation(configuration: configuration, baseUrl: gitBaseUrl, testTargetSourceFiles: testTargetSourceFiles, filePatterns: filePatterns, device: device, plugin: testExtractionPlugin)
        let testDistributionOperation = TestDistributionOperation(device: device, plugin: testDistributionPlugin)
        let simulatorSetupOperation = SimulatorSetupOperation(configuration: configuration, nodes: uniqueNodes, device: device)
        let simulatorBootOperation = SimulatorBootOperation()
        let simulatorWakeupOperation = SimulatorWakeupOperation(nodes: uniqueNodes)
        let distributeTestBundleOperation = DistributeTestBundleOperation(nodes: uniqueNodes)
        let testRunnerOperation = TestRunnerOperation(configuration: configuration, buildTarget: targets.build.name, testTarget: targets.test.name)
        let testCollectorOperation = TestCollectorOperation(configuration: configuration, timestamp: timestamp, buildTarget: targets.build.name, testTarget: targets.test.name)
        let codeCoverageCollectionOperation = CodeCoverageCollectionOperation(configuration: configuration, baseUrl: gitBaseUrl, timestamp: timestamp)
        let testTearDownOperation = TestTearDownOperation(configuration: configuration, timestamp: timestamp)
        let cleanupOperation = CleanupOperation(configuration: configuration, timestamp: timestamp)
        let simulatorTearDownOperation = SimulatorTearDownOperation(configuration: configuration, nodes: uniqueNodes)
        let tearDownOperation = TearDownOperation(configuration: configuration, plugin: tearDownPlugin)
        
        let operations: [Operation & LoggedOperation] =
            [validationOperation,
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
             codeCoverageCollectionOperation,
             testTearDownOperation,
             simulatorTearDownOperation,
             cleanupOperation,
             tearDownOperation]
        
        localSetupOperation.addDependency(validationOperation)
        
        setupOperation.addDependency(localSetupOperation)
        testExtractionOperation.addDependency(localSetupOperation)
        wakeupOperation.addDependency(localSetupOperation)
        
        compileOperation.addDependency(setupOperation)
        simulatorSetupOperation.addDependencies([setupOperation, wakeupOperation])
        
        testDistributionOperation.addDependency(testExtractionOperation)
        testDistributionOperation.addDependency(simulatorSetupOperation)
        
        simulatorBootOperation.addDependency(simulatorSetupOperation)
        simulatorWakeupOperation.addDependency(simulatorBootOperation)
        
        distributeTestBundleOperation.addDependency(compileOperation)
        
        testRunnerOperation.addDependencies([simulatorWakeupOperation, distributeTestBundleOperation, testDistributionOperation])
        
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
                
                print("\n💥 \(op.className) did throw exception\n")
                
                self.tearDown(operations: operations, testSessionResult: testSessionResult, error: opError as? Error)
            }
        }
        
        validationOperation.didStart = { [unowned self] in
            try? self.eventPlugin.run(event: Event(kind: .start, info: [:]), device: device)
        }
        validationOperation.didThrow = { [unowned self] opError in
            try? self.eventPlugin.run(event: Event(kind: .stop, info: ["error": opError.localizedDescription]), device: device)
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
        
        simulatorSetupOperation.didEnd = { simulators in
            testDistributionOperation.simulatorCount = simulators.count
            simulatorBootOperation.simulators = simulators
            testRunnerOperation.simulators = simulators
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
                testSessionResult.failedTests = testCaseResults.filter { $0.status == .failed }
            
                let nodes = Set(testCaseResults.map { $0.node })
                for node in nodes {
                    let testCases = testCaseResults.filter { $0.node == node }
                    guard testCases.count > 0 else { continue }
                    
                    let executionTime = testCases.reduce(0.0, { $0 + $1.duration })
                    testSessionResult.nodes[node] = .init(executionTime: executionTime, totalTests: testCases.count)
                    
                    for summaryPlist in Set(testCases.map { $0.summaryPlistPath }) {
                        testSessionResult.summaryPlistPath[summaryPlist] = node
                    }
                }
            }
            
            testCollectorOperation.testCaseResults = testCaseResults
            testTearDownOperation.testCaseResults = testCaseResults
            try? self.eventPlugin.run(event: Event(kind: .stopTesting, info: [:]), device: device)
        }
        
        tearDownOperation.didStart = { [unowned tearDownOperation] in
            tearDownOperation.testSessionResult = testSessionResult
        }
        
        monitorOperationsExecutionTime(operations, testSessionResult: testSessionResult)
        dispatchTimeout(operations: operations, testSessionResult: testSessionResult)
        
        return operations
    }
    
    private func tearDown(operations: [Operation & LoggedOperation], testSessionResult: TestSessionResult, error: Error?) {
        operations.forEach { $0.cancel() }

        let logger = ExecuterLogger(name: "Test", address: "localhost")
        
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
                try eventPlugin.run(event: Event(kind: .stop, info: ["error": error.localizedDescription]), device: userOptions.device)
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
    
    private func dispatchTimeout(operations: [Operation & LoggedOperation], testSessionResult: TestSessionResult) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + TimeInterval(userOptions.timeoutMinutes * 60)) { [unowned self] in
            self.tearDown(operations: operations, testSessionResult: testSessionResult, error: Error("💥 ⏰ Dispatch did timeout!\n".bold))
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
