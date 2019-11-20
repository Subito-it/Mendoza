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
        return makeConnectionPool(sources: configuration.nodes)
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
            
            let destinationPath = "\(self.configuration.resultDestination.path)/\(self.timestamp)"
            
            guard let testCaseResults = testCaseResults else { fatalError("💣 Required field `testCaseResults` not set") }

            let testNodes = Set(testCaseResults.map { $0.node })            
            try pool.execute { [unowned self] (executer, source) in
                guard testNodes.contains(source.node.address) else {
                    return
                }
                
                let logPath = "\(Path.logs.rawValue)/*"
                try executer.rsync(sourcePath: logPath, destinationPath: destinationPath, on: destinationNode)
                let resultsPath = "\(Path.results.rawValue)/*"
                try executer.rsync(sourcePath: resultsPath, destinationPath: destinationPath, on: destinationNode)

                try self.clearDiagnosticReports(executer: executer)
            }
            
            try self.mergeResults(destinationNode: destinationNode, destinationPath: destinationPath)
            
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
        
        let executer = try destinationNode.makeExecuter(logger: logger)
        let sourcePaths = try executer.execute("find \(destinationPath) -type d -name '*.xcresult'").components(separatedBy: "\n")
        
        let mergedDestinationPath = "\(destinationPath)/\(Environment.xcresultFilename)"
        let mergeCmd = "xcrun xcresulttool merge " + sourcePaths.map { "\"\($0)\"" }.joined(separator: " ") + " --output-path \(mergedDestinationPath)"
        _ = try executer.execute(mergeCmd)
        
        let cleanupCmd = "rm -rf " + sourcePaths.map { "\"\($0)\"" }.joined(separator: " ")
        _ = try executer.execute(cleanupCmd)
    }
}
