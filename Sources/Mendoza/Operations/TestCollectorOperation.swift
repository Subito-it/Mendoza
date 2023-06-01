//
//  TestCollectorOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestCollectorOperation: BaseOperation<[TestCaseResult]> {
    var testCaseResults: [TestCaseResult]?

    private let configuration: Configuration
    private lazy var pool: ConnectionPool = {
        makeConnectionPool(sources: configuration.nodes)
    }()

    private let mergeResults: Bool
    private let destinationPath: String
    private let productNames: [String]

    init(configuration: Configuration, mergeResults: Bool, destinationPath: String, productNames: [String]) {
        self.configuration = configuration
        self.mergeResults = mergeResults
        self.destinationPath = destinationPath
        self.productNames = productNames
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let destinationNode = configuration.resultDestination.node

            guard var testCaseResults = testCaseResults else { fatalError("💣 Required field `testCaseResults` not set") }

            let testNodes = Set(testCaseResults.map(\.node))
            try pool.execute { [unowned self] executer, source in
                guard testNodes.contains(source.node.address) else { return }

                // Copy code coverage files
                let logPath = "\(Path.logs.rawValue)/*"
                try executer.rsync(sourcePath: logPath, destinationPath: destinationPath, include: ["*/", "*.profdata"], exclude: ["*"], on: destinationNode)

                try self.clearDiagnosticReports(executer: executer)
            }
            
            let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
            addLogger(logger)
            let executer = try destinationNode.makeExecuter(logger: logger, environment: nodesEnvironment[destinationNode.address] ?? [:])
            
            let results = try executer.execute("find '\(destinationPath)' -type f -name '*.profdata'").components(separatedBy: "\n")
            
            var moveCommands = [String]()
            for (index, result) in results.enumerated() where !result.isEmpty {
                moveCommands.append("mv '\(result)' '\(destinationPath)/\(index).profdata'")
            }
            _ = try executer.execute(moveCommands.joined(separator: "; "))

            if self.mergeResults {
                try mergeResults(destinationNode: destinationNode, destinationPath: destinationPath, destinationName: Environment.xcresultFilename)
                
                let totalResults = testCaseResults.count
                for index in 0..<totalResults {
                    testCaseResults[index].xcResultPath = Environment.xcresultFilename
                }
            } else {
                let results = try executer.execute("find '\(destinationPath)' -type d -name '*.xcresult'").components(separatedBy: "\n")
                
                let lastTwoPathComponents: (String) -> String = { path in
                    let components = path.components(separatedBy: "/")
                    guard components.count > 2 else { return path }
                    return "\(components[components.count - 2])/\(components[components.count - 1])"
                }
                
                var moveCommands = [String]()
                for (index, result) in results.enumerated() {
                    let updatedResultPath = "\(destinationPath)/\(index).xcresult"
                    moveCommands.append("mv '\(result)' '\(updatedResultPath)'")
                    if let index = testCaseResults.firstIndex(where: { lastTwoPathComponents($0.xcResultPath) == lastTwoPathComponents(result) }) {
                        testCaseResults[index].xcResultPath = lastTwoPathComponents(updatedResultPath)
                    }
                }
                _ = try executer.execute(moveCommands.joined(separator: "; "))
            }
            
            try cleanupEmptyFolders(executer: executer, destinationPath: destinationPath)

            didEnd?(testCaseResults)
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
    
    private func cleanupEmptyFolders(executer: Executer, destinationPath: String) throws {
            _ = try executer.execute("find '\(destinationPath)' -type d -empty -delete")

    }

    private func clearDiagnosticReports(executer: Executer) throws {
        for productName in productNames {
            let path = "~/Library/Logs/DiagnosticReports/\(productName)_*"

            _ = try executer.execute("rm -f \(path) || true")
        }
    }

    private func mergeResults(destinationNode: Node, destinationPath: String, destinationName: String) throws {
        guard !destinationPath.isEmpty else { return }

        let logger = ExecuterLogger(name: "TestCollectorOperation-Merge", address: destinationNode.address)
        addLogger(logger)

        let mergedDestinationPath = "\(destinationPath)/\(destinationName)"

        let executer = try destinationNode.makeExecuter(logger: logger, environment: nodesEnvironment[destinationNode.address] ?? [:])
        let sourcePaths = try executer.execute("find \(destinationPath) -type d -name '*.xcresult'").components(separatedBy: "\n")

        let mergeCmd: (_ sourcePaths: [String], _ destinationPath: String) -> String = { "xcrun xcresulttool merge " + $0.map { "'\($0)'" }.joined(separator: " ") + " --output-path '\($1)' 2>/dev/null" }
        
        // Merge in batch of ~ 50 results
            
        let partsCount = sourcePaths.count / 50
        let sourcePathsParts = sourcePaths.split(in: partsCount)
        var partialMerges = [String]()
        
        if partsCount > 1 {
            let queue = OperationQueue()
            let syncQueue = DispatchQueue(label: "com.subito.mendoza.collector.queue", qos: .userInitiated)
            var mergeFailed = false

            for (index, part) in sourcePathsParts.enumerated() {
                queue.addOperation {
                    let partialMergeDestination = mergedDestinationPath + index.description
                    do {
                        let partialLogger = ExecuterLogger(name: "\(logger.name)-\(index)", address: logger.address)
                        let executer = try destinationNode.makeExecuter(logger: partialLogger, environment: self.nodesEnvironment[destinationNode.address] ?? [:])
                        _ = try executer.execute(mergeCmd(part, partialMergeDestination))
                    } catch {
                        syncQueue.sync { mergeFailed = true }
                    }
                    
                    syncQueue.sync { partialMerges.append(partialMergeDestination) }
                }
            }
            
            queue.waitUntilAllOperationsAreFinished()
            
            guard !mergeFailed else {
                throw Error("Result merge failed")
            }
        } else {
            partialMerges = sourcePaths
        }

        guard partialMerges.isEmpty == false else { return }

        if partialMerges.count > 1 {
            _ = try executer.execute(mergeCmd(partialMerges, mergedDestinationPath))
        } else {
            let moveCommand = "mv '\(partialMerges[0])' '\(mergedDestinationPath)'"
            _ = try executer.execute(moveCommand)
        }
        
        let pathsToDelete = (sourcePaths + partialMerges).uniqued().filter { $0.hasPrefix(destinationPath) }
        let cleanupCmd = "rm -rf " + pathsToDelete.map { "'\($0)'" }.joined(separator: " ")
        _ = try executer.execute(cleanupCmd)
    }
}


