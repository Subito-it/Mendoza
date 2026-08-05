//
//  Test+MakeOperations.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

extension Test {
    func makeOperations(gitStatus: GitStatus, testSessionResult: TestSessionResult, sdk: String) throws -> [RunOperation] {
        let resultDestinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.resultFoldername)".pathExpandingTilde()

        let filePatterns = configuration.building.filePatterns
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
        let simulatorSetupOperation = SimulatorSetupOperation(buildBundleIdentifier: configuration.building.buildBundleIdentifier, testBundleIdentifier: configuration.building.testBundleIdentifier, nodes: uniqueNodes, device: device, alwaysRebootSimulators: configuration.testing.alwaysRebootSimulators, disabledSimulatorServices: configuration.testing.disabledSimulatorServices, verbose: configuration.verbose)
        let processKillerOperation = ProcessKillerOperation(nodes: uniqueNodes)
        let distributeTestBundleOperation = DistributeTestBundleOperation(nodes: uniqueNodes)
        let testRunnerOperation = TestRunnerOperation(configuration: configuration, baseUrl: gitBaseUrl, destinationPath: resultDestinationPath, testTarget: targets.test.name, productNames: productNames)
        let testCollectorOperation = TestCollectorOperation(configuration: configuration, destinationPath: resultDestinationPath, productNames: productNames)

        let codeCoverageCollectionOperation = CodeCoverageCollectionOperation(configuration: configuration, baseUrl: gitBaseUrl, timestamp: timestamp)
        let cleanupOperation = CleanupOperation(resultDestination: configuration.resultDestination, timestamp: timestamp)
        let simulatorTearDownOperation = SimulatorTearDownOperation(nodes: uniqueNodes, verbose: configuration.verbose)
        let tearDownOperation = TearDownOperation(configuration: configuration, git: gitStatus, timestamp: timestamp, plugin: tearDownPlugin)

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
                // Handle NoTestCasesFoundError gracefully - not a failure, just early termination
                if opError is NoTestCasesFoundError {
                    print("\nℹ️  No test cases found to execute\n".yellow)
                    self.cancelOperation(operations)
                    let noTestsTearDownOperation = TearDownOperation(configuration: self.configuration, git: gitStatus, timestamp: self.timestamp, plugin: tearDownPlugin)
                    noTestsTearDownOperation.testSessionResult = testSessionResult
                    noTestsTearDownOperation.main()
                    return
                }

                if (opError as? Error)?.didLogError == false {
                    op.logger.log(exception: opError.localizedDescription)
                }

                print("\n💣 \(op.className.components(separatedBy: ".").last ?? op.className) did throw exception, see session logs for details on what went wrong\n")
                if opError.localizedDescription.count < 2_000 {
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

        tearDownOperation.didEnd = { [unowned self] _ in
            self.tearDown(operations: operations, testSessionResult: testSessionResult, error: nil)
        }

        monitorOperationsExecutionTime(operations, testSessionResult: testSessionResult)

        return operations
    }
}
