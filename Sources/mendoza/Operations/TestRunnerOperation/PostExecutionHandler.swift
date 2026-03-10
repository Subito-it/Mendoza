//
//  PostExecutionHandler.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Handles post-test-execution tasks including rsync of results and individual coverage generation
class PostExecutionHandler {
    private let configuration: Configuration
    private let baseUrl: URL
    private let destinationPath: String

    init(configuration: Configuration, baseUrl: URL, destinationPath: String) {
        self.configuration = configuration
        self.baseUrl = baseUrl
        self.destinationPath = destinationPath
    }

    /// Process post-execution tasks for a completed test
    /// This includes syncing xcresult to destination and generating individual coverage reports
    func process(
        executer: Executer,
        testRunner: TestRunner,
        testCaseResult: TestCaseResult?,
        individualCoverageFile: String?
    ) {
        guard let xcResultPath = testCaseResult?.xcResultPath,
              xcResultPath.hasPrefix(Path.base.rawValue) else { return }

        let destinationNode = configuration.resultDestination.node
        let runnerDestinationPath = "\(destinationPath)/\(testRunner.id)"

        // Sync xcresult to destination node
        try? executer.rsync(sourcePath: xcResultPath, destinationPath: runnerDestinationPath, on: destinationNode)
        _ = try? executer.execute("rm -rf '\(xcResultPath)'")

        // Generate individual test coverage if enabled
        generateIndividualCoverage(
            executer: executer,
            testCaseResult: testCaseResult,
            individualCoverageFile: individualCoverageFile
        )
    }

    private func generateIndividualCoverage(
        executer: Executer,
        testCaseResult: TestCaseResult?,
        individualCoverageFile: String?
    ) {
        guard let testCaseResult = testCaseResult,
              let individualCoverageFile = individualCoverageFile,
              configuration.testing.extractIndividualTestCoverage || configuration.testing.extractTestCoveredFiles else {
            return
        }

        do {
            let pathEquivalence = configuration.testing.codeCoveragePathEquivalence
            let coverageUrl = URL(filePath: individualCoverageFile)

            let codeCoverageGenerator = CodeCoverageGenerator(configuration: configuration, baseUrl: baseUrl)
            let jsonCoverageSummaryUrl = try codeCoverageGenerator.generateJsonCoverage(
                executer: executer,
                coverageUrl: coverageUrl,
                summary: true,
                pathEquivalence: pathEquivalence
            )

            if configuration.testing.extractTestCoveredFiles {
                let filename = "\(testCaseResult.suite)-\(testCaseResult.name)-\(Int(testCaseResult.startInterval)).json"
                _ = try executer.execute("mendoza mendoza extract_files_coverage '\(jsonCoverageSummaryUrl.path)' '\(Path.testFileCoverage.rawValue)/\(filename)'")
            }

            if configuration.testing.extractIndividualTestCoverage {
                let filename = "\(testCaseResult.suite)-\(testCaseResult.name)-\(Int(testCaseResult.startInterval)).json"
                _ = try executer.execute("mv '\(jsonCoverageSummaryUrl.path)' '\(Path.individualCoverage.rawValue)/\(filename)'")
            }

            // Clean up the individual profdata file after processing
            _ = try? executer.execute("rm -f '\(individualCoverageFile)'")
        } catch {
            print("🆘 failed generating individual code coverage. error: \(error)")
        }
    }
}
