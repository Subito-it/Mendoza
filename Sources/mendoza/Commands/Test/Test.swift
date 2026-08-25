//
//  Test.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

class Test {
    typealias RunOperation = BenchmarkedOperation & LoggedOperation

    var didFail: ((Swift.Error) -> Void)?

    // swiftlint:disable:next large_tuple
    let configuration: Configuration
    let eventPlugin: EventPlugin
    let pluginUrl: URL?
    let syncQueue = DispatchQueue(label: String(describing: Test.self))
    let timestamp: String
    var observers = [NSKeyValueObservation]()

    init(configuration: Configuration, pluginUrl: URL?) throws {
        self.configuration = configuration
        self.pluginUrl = pluginUrl

        self.eventPlugin = EventPlugin(baseUrl: pluginUrl, plugin: configuration.plugins)

        self.timestamp = Test.currentTimestamp()
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
    }

    func tearDown(operations: [RunOperation], testSessionResult: TestSessionResult, error: Error?) {
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

            // `try?`, like every other event call site: an event plugin reports on a session, it
            // does not decide its outcome. Letting it throw here made a non-zero exit from e.g. a
            // notification script surface as a failed session even when every test passed.
            if let error = error {
                try? eventPlugin.run(event: Event(kind: .error, info: ["error": error.localizedDescription]), device: device)
                didFail?(error)
            } else {
                try? eventPlugin.run(event: Event(kind: .stop, info: [:]), device: device)
            }
        } catch {
            try? dumpOperationLogs(operations)
            try? eventPlugin.run(event: Event(kind: .error, info: ["error": error.localizedDescription]), device: device)
            didFail?(error)
        }
    }

    func cancelOperation(_ operations: [Operation]) {
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

    func monitorOperationsExecutionTime(_ operations: [Operation], testSessionResult: TestSessionResult) {
        for op in operations {
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

            observers.append(observer)
        }
    }
}

extension Test {
    static func currentTimestamp() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"

        return dateFormatter.string(from: Date())
    }

    func dumpOperationLogs(_ operations: [LoggedOperation]) throws {
        // EventPlugin belongs to Test rather than to an operation, so unlike every other plugin its
        // logger reaches no operation's `loggers` set and has to be added by hand. Since event
        // plugin failures are ignored by design, this log is the only place its stderr shows up.
        let loggerCoordinator = LoggerCoordinator(loggers: operations.flatMap(\.loggers) + [eventPlugin.logger])

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

extension TestSessionResult {
    func copy() -> TestSessionResult? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(TestSessionResult.self, from: data)
    }
}

extension String {
    func pathExpandingTilde() -> String {
        replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
