//
//  TestCollectorOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestCollectorOperation: BaseOperation<Void> {
    var testCaseResults: [TestCaseResult]?

    private let configuration: Configuration
    private lazy var pool: ConnectionPool = {
        makeConnectionPool(sources: configuration.nodes)
    }()

    private let timestamp: String
    private let buildTarget: String
    private let testTarget: String

    init(configuration: Configuration, timestamp: String, buildTarget: String, testTarget: String) {
        self.configuration = configuration
        self.timestamp = timestamp
        self.buildTarget = buildTarget
        self.testTarget = testTarget
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let destinationNode = configuration.resultDestination.node

            let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)"

            guard let testCaseResults = testCaseResults else { fatalError("💣 Required field `testCaseResults` not set") }

            let testNodes = Set(testCaseResults.map(\.node))
            try pool.execute { [unowned self] executer, source in
                guard testNodes.contains(source.node.address) else {
                    return
                }

                let logPath = "\(Path.logs.rawValue)/*"
                try executer.rsync(sourcePath: logPath, destinationPath: destinationPath, on: destinationNode)
                let resultsPath = "\(Path.results.rawValue)/*"
                try executer.rsync(sourcePath: resultsPath, destinationPath: destinationPath, on: destinationNode)

                try self.clearDiagnosticReports(executer: executer)
            }

            try mergeResults(destinationNode: destinationNode, destinationPath: destinationPath)

            didEnd?(())
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

    private func clearDiagnosticReports(executer: Executer) throws {
        let path1 = "~/Library/Logs/DiagnosticReports/\(buildTarget)*"
        let path2 = "~/Library/Logs/DiagnosticReports/\(testTarget)*"

        _ = try executer.execute("rm \(path1) || true")
        _ = try executer.execute("rm \(path2) || true")
    }

    private func mergeResults(destinationNode: Node, destinationPath: String) throws {
        let logger = ExecuterLogger(name: "TestCollectorOperation-Merge", address: destinationNode.address)
        loggers.insert(logger)

        let mergedDestinationPath = "\(destinationPath)/\(Environment.xcresultFilename)"

        let executer = try destinationNode.makeExecuter(logger: logger)
        let sourcePaths = try executer.execute("find \(destinationPath) -type d -name '*.xcresult'").components(separatedBy: "\n")

        let mergeCmd: (_ sourcePaths: [String], _ destinationPath: String) -> String = { "xcrun xcresulttool merge " + $0.map { "'\($0)'" }.joined(separator: " ") + " --output-path '\($1)'" }

        // Merge in batch of 100 results

        let partsCount = sourcePaths.count / 100
        let sourcePathsParts = sourcePaths.split(in: partsCount)
        var partialMerges = [String]()
        for (index, part) in sourcePathsParts.enumerated() {
            if part.count > 1 {
                let partialMergeDestination = mergedDestinationPath + index.description
                _ = try executer.execute(mergeCmd(part, partialMergeDestination))
                partialMerges.append(partialMergeDestination)
            } else {
                partialMerges = part
            }
        }

        guard partialMerges.isEmpty == false else { return }

        if partialMerges.count > 1 {
            _ = try executer.execute(mergeCmd(partialMerges, mergedDestinationPath))
        } else {
            let moveCommand = "mv '\(partialMerges[0])' '\(mergedDestinationPath)'"
            _ = try executer.execute(moveCommand)
        }

        let cleanupCmd = "rm -rf " + (sourcePaths + partialMerges).map { "'\($0)'" }.joined(separator: " ")
        _ = try executer.execute(cleanupCmd)
    }
}
