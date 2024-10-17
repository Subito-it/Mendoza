//
//  CodeCoverageCollectionOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 09/06/2021.
//

import Foundation

class CodeCoverageCollectionOperation: BaseOperation<Coverage?> {
    private lazy var executer: Executer = makeLocalExecuter()

    private let configuration: Configuration
    private let baseUrl: URL
    private let timestamp: String
    private lazy var codeCoverageGenerator = CodeCoverageGenerator(
        configuration: configuration, baseUrl: baseUrl)

    init(configuration: Configuration, baseUrl: URL, timestamp: String) {
        self.configuration = configuration
        self.baseUrl = baseUrl
        self.timestamp = timestamp
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let resultDestination = configuration.resultDestination
            let destinationNode = resultDestination.node

            let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
            let destinationExecuter = try destinationNode.makeExecuter(
                logger: logger, environment: nodesEnvironment[destinationNode.address] ?? [:])

            let resultPath = "\(resultDestination.path)/\(timestamp)"

            let coverageFiles = try executer.execute(
                "find '\(resultPath)' -type f -name '*.profdata'"
            ).components(separatedBy: "\n")

            var coverage: Coverage? = nil
            let coverageMerger = CodeCoverageMerger(executer: destinationExecuter)
            if let mergedPath = try coverageMerger.merge(coverageFiles: coverageFiles) {
                let localCoverageUrl = Path.temp.url.appendingPathComponent(
                    "\(UUID().uuidString).profdata")
                try destinationExecuter.download(remotePath: mergedPath, localUrl: localCoverageUrl)

                let pathEquivalence = configuration.testing.codeCoveragePathEquivalence
                let jsonCoverageUrl = try codeCoverageGenerator.generateJsonCoverage(
                    executer: executer, coverageUrl: localCoverageUrl, summary: false,
                    pathEquivalence: pathEquivalence)
                let jsonCoverageSummaryUrl = try codeCoverageGenerator.generateJsonCoverage(
                    executer: executer, coverageUrl: localCoverageUrl, summary: true,
                    pathEquivalence: pathEquivalence)
                let htmlCoverageSummaryUrl = try codeCoverageGenerator.generateHtmlCoverage(
                    executer: executer, coverageUrl: localCoverageUrl,
                    pathEquivalence: pathEquivalence)

                try destinationExecuter.upload(
                    localUrl: jsonCoverageSummaryUrl,
                    remotePath:
                        "\(resultPath)/\(Environment.resultFoldername)/\(Environment.coverageSummaryFilename)"
                )
                try destinationExecuter.upload(
                    localUrl: jsonCoverageUrl,
                    remotePath:
                        "\(resultPath)/\(Environment.resultFoldername)/\(Environment.coverageFilename)"
                )
                try destinationExecuter.upload(
                    localUrl: htmlCoverageSummaryUrl,
                    remotePath:
                        "\(resultPath)/\(Environment.resultFoldername)/\(Environment.coverageHtmlFilename)"
                )

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

    override func cancel() {
        if isExecuting {
            executer.terminate()
        }
        super.cancel()
    }
}
