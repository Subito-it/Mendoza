//
//  CodeCoverageCollectionOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 09/06/2021.
//

import Foundation

class CodeCoverageCollectionOperation: BaseOperation<Coverage?> {
    private lazy var executer: Executer = makeLocalExecuter()

    private let resultDestination: ConfigurationResultDestination
    private let buildBundleIdentifier: String
    private let pathEquivalence: String?
    private let baseUrl: URL
    private let timestamp: String

    init(resultDestination: ConfigurationResultDestination, buildBundleIdentifier: String, pathEquivalence: String?, baseUrl: URL, timestamp: String) {
        self.resultDestination = resultDestination
        self.buildBundleIdentifier = buildBundleIdentifier
        self.pathEquivalence = pathEquivalence
        self.baseUrl = baseUrl
        self.timestamp = timestamp
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let destinationNode = resultDestination.node

            let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
            let destinationExecuter = try destinationNode.makeExecuter(logger: logger, environment: nodesEnvironment[destinationNode.address] ?? [:])

            let resultPath = "\(resultDestination.path)/\(timestamp)"

            var coverage: Coverage? = nil
            let coverageMerger = CodeCoverageMerger(executer: destinationExecuter, searchPath: resultPath)
            if let mergedPath = try coverageMerger.merge() {
                let localCoverageUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).profdata")
                try destinationExecuter.download(remotePath: mergedPath, localUrl: localCoverageUrl)

                let jsonCoverageUrl = try generateJsonCoverage(coverageUrl: localCoverageUrl, summary: false, pathEquivalence: pathEquivalence)
                let jsonCoverageSummaryUrl = try generateJsonCoverage(coverageUrl: localCoverageUrl, summary: true, pathEquivalence: pathEquivalence)
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

    private func generateJsonCoverage(coverageUrl: URL, summary: Bool, pathEquivalence: String?) throws -> URL {
        let executablePath = try findExecutablePath(executer: executer, buildBundleIdentifier: buildBundleIdentifier)
        let summaryParameter = summary ? "--summary-only" : ""
        let truncateDecimals = #"| sed -E 's/(percent":[0-9]*\.[0-9])[0-9]*/\1/g'"#
        var cmd = "xcrun llvm-cov export -instr-profile \(coverageUrl.path) \(executablePath) \(summaryParameter) \(truncateDecimals)"

        if let pathEquivalence {
            cmd += sedsCommand(from: pathEquivalence)
        }

        let stripBasePath = #" | sed 's|\#(baseUrl.path + "/")||g'"#
        cmd += stripBasePath

        let url = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")
        _ = try executer.execute("\(cmd) > \(url.path)")

        return url
    }

    private func generateHtmlCoverage(coverageUrl: URL, pathEquivalence: String?) throws -> URL {
        let executablePath = try findExecutablePath(executer: executer, buildBundleIdentifier: buildBundleIdentifier)
        var cmd = "xcrun llvm-cov show --format=html -instr-profile \(coverageUrl.path) \(executablePath)"

        if let pathEquivalence {
            cmd += llvmCovPathEquivalenceParameters(from: pathEquivalence)
            cmd += sedsCommand(from: pathEquivalence)
        }

        let stripBasePath = #" | sed 's|\#(baseUrl.path + "/")||g'"#
        cmd += stripBasePath

        let url = Path.temp.url.appendingPathComponent("\(UUID().uuidString).html")
        _ = try executer.execute("\(cmd) > \(url.path)")

        return url
    }

    /// Convert path equivalence parameters formats from Mendoza (single comma separated) to llvm-cov (multiple parameters)
    private func llvmCovPathEquivalenceParameters(from pathEquivalence: String) -> String {
        let components = pathEquivalence.components(separatedBy: ",")
        guard components.count % 2 == 0 else {
            print("Invalid pathEquivalence format. It must contain an even number of elements.")
            return ""
        }

        var parameters = ""

        for i in stride(from: 0, to: components.count, by: 2) {
            let source = components[i]
            let destination = components[i + 1]
            parameters += " --path-equivalence=\(source),\(destination)"
        }

        return parameters
    }

    /// These seds will replace paths in the generated .json and .html format to match the provided pathEquivalence
    private func sedsCommand(from pathEquivalence: String) -> String {
        let components = pathEquivalence.components(separatedBy: ",")
        guard components.count % 2 == 0 else {
            print("Invalid pathEquivalence format. It must contain an even number of elements.")
            return ""
        }

        var cmd = ""

        for i in stride(from: 0, to: components.count, by: 2) {
            let source = components[i].replacingOccurrences(of: ".", with: #"\."#) // Escape dots for sed
            let destination = components[i + 1]

            cmd += " | sed 's|\(source)|\(destination)|g'"
        }

        return cmd
    }

    override func cancel() {
        if isExecuting {
            executer.terminate()
        }
        super.cancel()
    }
}
