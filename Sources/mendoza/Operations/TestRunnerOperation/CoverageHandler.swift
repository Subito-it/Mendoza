//
//  CoverageHandler.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Handles coverage file operations including progressive merging and individual test coverage extraction
class CoverageHandler {
    private let verbose: Bool

    init(verbose: Bool) {
        self.verbose = verbose
    }

    /// Find all .profdata files in the given path
    func findCoverageFiles(executer: Executer, coveragePath: String) throws -> [String] {
        try executer.execute("find '\(coveragePath)' -type f -name '*.profdata'")
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }

    /// Find the newly created profdata from xcodebuild (non-UUID named file)
    /// UUID-named files are from previous merges, so we exclude them
    func findNewCoverageFile(in files: [String]) -> String? {
        files.first { path in
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return UUID(uuidString: filename) == nil
        }
    }

    /// Save individual test coverage profdata before merging
    /// - Returns: Path to the saved individual coverage file, or nil if not saved
    func saveIndividualCoverage(
        executer: Executer,
        testCaseResult: TestCaseResult,
        newCoverageFile: String,
        searchPath: String
    ) -> String? {
        let filename = "\(testCaseResult.suite)-\(testCaseResult.name)-\(Int(testCaseResult.startInterval)).profdata"
        let individualPath = "\(searchPath)/\(filename)"
        _ = try? executer.execute("cp '\(newCoverageFile)' '\(individualPath)'")
        return individualPath
    }

    /// Perform progressive merge of all profdata files
    /// This reduces work at the end of execution by merging incrementally
    func progressiveMerge(
        executer: Executer,
        coverageFiles: [String],
        nodeAddress: String,
        runnerIndex: Int
    ) {
        let coverageMerger = CodeCoverageMerger(executer: executer)
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? coverageMerger.merge(coverageFiles: coverageFiles)
        if verbose {
            print("🙈 [\(Date().description)] Node \(nodeAddress) took \(CFAbsoluteTimeGetCurrent() - start)s for coverage merge {\(runnerIndex)}".magenta)
        }
    }
}
