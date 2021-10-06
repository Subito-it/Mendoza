//
//  CodeCoverageCollectionOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 09/06/2021.
//

import Foundation

class CodeCoverageCollectionOperation: BaseOperation<Coverage?> {
    private lazy var executer: Executer = {
        return makeLocalExecuter()
    }()
    private let configuration: Configuration
    private let pathEquivalence: String?
    private let baseUrl: URL
    private let timestamp: String
    
    init(configuration: Configuration, pathEquivalence: String?, baseUrl: URL, timestamp: String) {
        self.configuration = configuration
        self.pathEquivalence = pathEquivalence
        self.baseUrl = baseUrl
        self.timestamp = timestamp
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            let destinationNode = configuration.resultDestination.node
            
            let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
            let destinationExecuter = try destinationNode.makeExecuter(logger: logger)
            
            let resultPath = "\(configuration.resultDestination.path)/\(timestamp)"
            
            var coverage: Coverage? = nil
            let coverageMerger = CodeCoverageMerger(executer: destinationExecuter, searchPath: resultPath)
            if let mergedPath = try coverageMerger.merge() {
                let localCoverageUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).profdata")
                try destinationExecuter.download(remotePath: mergedPath, localUrl: localCoverageUrl)
                
                let jsonCoverageUrl = try generateJsonCoverage(coverageUrl: localCoverageUrl, summary: false)
                let jsonCoverageSummaryUrl = try generateJsonCoverage(coverageUrl: localCoverageUrl, summary: true)
                let htmlCoverageSummaryUrl = try generateHtmlCoverage(coverageUrl: localCoverageUrl, pathEquivalence: pathEquivalence)

                try destinationExecuter.upload(localUrl: jsonCoverageSummaryUrl, remotePath: "\(resultPath)/\(Environment.resultFoldername)/\(Environment.coverageSummaryFilename)")
                try destinationExecuter.upload(localUrl: jsonCoverageUrl, remotePath: "\(resultPath)/\(Environment.resultFoldername)/\(Environment.coverageFilename)")
                try destinationExecuter.upload(localUrl: htmlCoverageSummaryUrl, remotePath: "\(resultPath)/\(Environment.resultFoldername)/\(Environment.coverageHtmlFilename)")
                
                if let coverageData = try? Data(contentsOf: jsonCoverageSummaryUrl) {
                    coverage = try? JSONDecoder().decode(Coverage.self, from: coverageData)
                }
                
                _ = try destinationExecuter.execute("rm -f \(mergedPath)")
            }

            didEnd?(coverage)
        } catch {
            didThrow?(error)
        }
    }
    
    private func generateJsonCoverage(coverageUrl: URL, summary: Bool) throws -> URL {
        let truncateDecimals = #"| sed -E 's/(percent":[0-9]*\.[0-9])[0-9]*/\1/g'"#
        let stripBasePath = #"| sed 's|\#(baseUrl.path + "/")||g'"#
        
        var replacePath = ""
        if let pathEquivalence = pathEquivalence,
           pathEquivalence.components(separatedBy: ",").count == 2 {
            let source = pathEquivalence.components(separatedBy: ",")[0]
            let destination = pathEquivalence.components(separatedBy: ",")[1]

            replacePath = "| sed 's|\(source)|\(destination)|g'"
        }
        
        let executablePath = try findExecutablePath(executer: executer, configuration: configuration)
        let url = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")
        let summaryParameter = summary ? "--summary-only" : ""
        let cmd = "xcrun llvm-cov export -instr-profile \(coverageUrl.path) \(executablePath) \(summaryParameter) \(truncateDecimals) \(replacePath) \(stripBasePath) > \(url.path)"
        
        _ = try executer.execute(cmd)

        return url
    }
    
    private func generateHtmlCoverage(coverageUrl: URL, pathEquivalence: String?) throws -> URL {
        let executablePath = try findExecutablePath(executer: executer, configuration: configuration)
        let url = Path.temp.url.appendingPathComponent("\(UUID().uuidString).html")
        var cmd = "xcrun llvm-cov show --format=html -instr-profile \(coverageUrl.path) \(executablePath)"
        
        if let pathEquivalence = pathEquivalence,
           pathEquivalence.components(separatedBy: ",").count == 2 {
            let source = pathEquivalence.components(separatedBy: ",")[0]
            let destination = pathEquivalence.components(separatedBy: ",")[1]

            cmd += " --path-equivalence=\(pathEquivalence) | sed 's|\(source)|\(destination)|g'"
        }

        let stripBasePath = #" | sed 's|\#(baseUrl.path + "/")||g'"#
        cmd += stripBasePath
        
        _ = try executer.execute("\(cmd) > \(url.path)")
        
        return url
    }

    override func cancel() {
        if isExecuting {
            executer.terminate()
        }
        super.cancel()
    }
}
