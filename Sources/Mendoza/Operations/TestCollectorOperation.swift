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

    private let mergeResults: Bool
    private let timestamp: String
    private let productNames: [String]
    private let loggersSyncQueue = DispatchQueue(label: String(describing: TestCollectorOperation.self))

    init(configuration: Configuration, mergeResults: Bool, timestamp: String, productNames: [String]) {
        self.configuration = configuration
        self.mergeResults = mergeResults
        self.timestamp = timestamp
        self.productNames = productNames
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let destinationNode = configuration.resultDestination.node

            let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.resultFoldername)"

            guard let testCaseResults = testCaseResults else { fatalError("💣 Required field `testCaseResults` not set") }

            let testNodes = Set(testCaseResults.map(\.node))
            try pool.execute { [unowned self] executer, source in
                guard testNodes.contains(source.node.address) else {
                    return
                }
                
                // Copy code coverage files
                let logPath = "\(Path.logs.rawValue)/*"
                try executer.rsync(sourcePath: logPath, destinationPath: destinationPath, include: ["*/", "*.profdata"], exclude: ["*"], on: destinationNode)

                // Remote merging of partial results can be performed by uncommenting these lib could be performed on remote node
                // if self.mergeResults {
                //     try mergeResults(destinationNode: source.node, destinationPath: Path.results.rawValue, destinationName: "\(UUID().uuidString).xcresult")
                // }

                let resultsPath = "\(Path.results.rawValue)/*"
                try executer.rsync(sourcePath: resultsPath, destinationPath: destinationPath, include: ["*.xcresult"], on: destinationNode)

                try self.clearDiagnosticReports(executer: executer)
            }
            
            let executer = try destinationNode.makeExecuter(logger: nil)
            
            let results = try executer.execute("find '\(destinationPath)' -type f -name '*.profdata'").components(separatedBy: "\n")
            
            var moveCommands = [String]()
            for (index, result) in results.enumerated() {
                moveCommands.append("mv '\(result)' '\(destinationPath)/\(index).profdata'")
            }
            _ = try executer.execute(moveCommands.joined(separator: "; "))

            if self.mergeResults {
                try mergeResults(destinationNode: destinationNode, destinationPath: destinationPath, destinationName: Environment.xcresultFilename)
            } else {
                let results = try executer.execute("find '\(destinationPath)' -type d -name '*.xcresult'").components(separatedBy: "\n")
                
                var moveCommands = [String]()
                for (index, result) in results.enumerated() {
                    moveCommands.append("mv '\(result)' '\(destinationPath)/\(index).xcresult'")
                }
                _ = try executer.execute(moveCommands.joined(separator: "; "))
            }
            
            try cleanupEmptyFolders(executer: executer, destinationPath: destinationPath)

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
        let logger = ExecuterLogger(name: "TestCollectorOperation-Merge", address: destinationNode.address)
        _ = loggersSyncQueue.sync { loggers.insert(logger) }

        let mergedDestinationPath = "\(destinationPath)/\(destinationName)"

        let executer = try destinationNode.makeExecuter(logger: logger)
        let sourcePaths = try executer.execute("find \(destinationPath) -type d -name '*.xcresult'").components(separatedBy: "\n")

        let mergeCmd: (_ sourcePaths: [String], _ destinationPath: String) -> String = { "xcrun xcresulttool merge " + $0.map { "'\($0)'" }.joined(separator: " ") + " --output-path '\($1)'" }
        
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
                        let executer = try destinationNode.makeExecuter(logger: partialLogger)
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

        let cleanupCmd = "rm -rf " + (sourcePaths + partialMerges).uniqued().map { "'\($0)'" }.joined(separator: " ")
        _ = try executer.execute(cleanupCmd)
    }
}
