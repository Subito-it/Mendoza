//
//  TestResultHandler.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Handles test result preview callbacks and status printing
class TestResultHandler {
    private let verbose: Bool

    init(verbose: Bool) {
        self.verbose = verbose
    }

    /// Print test result status to console
    func printStatus(
        _ result: TestCaseResult,
        testCase: TestCase,
        completedCount: Int,
        totalCount: Int,
        retryCount: Int,
        runnerIndex: Int
    ) {
        let timestamp = verbose ? "[\(Date().description)] " : ""
        let retryInfo = retryCount > 0 ? " (\(retryCount) retries)" : ""
        let duration = Int(result.duration.rounded(.up))

        switch result.status {
        case .passed:
            print("✅ \(timestamp)\(testCase.description) passed [\(completedCount)/\(totalCount)]\(retryInfo) in \(duration)s {\(runnerIndex)}".green)
        case .failed:
            print("❌ \(timestamp)\(testCase.description) failed [\(completedCount)/\(totalCount)]\(retryInfo) in \(duration)s {\(runnerIndex)}".red)
        }
    }

    /// Print retry enqueue message
    func printRetryEnqueue(_ testCase: TestCase, retryCount: Int) {
        if verbose {
            print("🔁  Renqueuing (no result) \(testCase), retry count: \(retryCount)".yellow)
        }
    }
}
