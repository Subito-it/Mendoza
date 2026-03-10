//
//  XCResultHandler.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Handles xcresult bundle operations including finding, moving, and disk space management
class XCResultHandler {
    private let xcresultBlobThresholdKB: Int?

    init(xcresultBlobThresholdKB: Int?) {
        self.xcresultBlobThresholdKB = xcresultBlobThresholdKB
    }

    /// Find the most recent xcresult bundle for a test runner
    /// In crash/retry scenarios, xcodebuild may create multiple bundles - this returns the newest
    func findTestResultUrl(executer: Executer, testRunner: TestRunner) throws -> URL? {
        let testResults = try findTestResultsUrl(executer: executer, testRunner: testRunner)
        guard let testResult = testResults.first else {
            // Under certain failures xcodebuild does not produce an .xcresult
            return nil
        }

        // Clean up older bundles in crash/retry scenarios
        if testResults.count > 1 {
            for olderResult in testResults.dropFirst() {
                _ = try? executer.execute("rm -rf '\(olderResult.path)'")
            }
        }

        return testResult
    }

    /// Find all xcresult bundles for a test runner, sorted by modification time (most recent first)
    func findTestResultsUrl(executer: Executer, testRunner: TestRunner) throws -> [URL] {
        let resultPath = Path.logs.url.appendingPathComponent(testRunner.id).path
        // Sort by modification time (most recent first) to handle crash scenarios
        let testResults = (try? executer.execute("find '\(resultPath)' -type d -name '*.xcresult' -exec stat -f '%m %N' {} \\; | sort -rn | cut -d' ' -f2-").components(separatedBy: "\n")) ?? []

        return testResults.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
    }

    /// Move xcresult to the results folder and return the new path
    func moveToResultsFolder(executer: Executer, xcResultUrl: URL, testRunner: TestRunner) throws -> String {
        let resultUrl = Path.results.url.appendingPathComponent(testRunner.id)
        _ = try executer.capture("mkdir -p '\(resultUrl.path)'; mv '\(xcResultUrl.path)' '\(resultUrl.path)'")
        return resultUrl.appendingPathComponent(xcResultUrl.lastPathComponent).path
    }

    /// Reclaim disk space by cleaning up large blobs in xcresult
    func reclaimDiskSpace(executer: Executer, path: String) throws {
        guard let thresholdKB = xcresultBlobThresholdKB else { return }
        _ = try? executer.execute(#"mendoza mendoza cleaunp_xcresult '\#(path)' \#(thresholdKB)"#)
    }

    /// Clean up previous test results before running a new test
    func cleanupPreviousResults(executer: Executer, testRunner: TestRunner) throws {
        let testResultsUrls = try findTestResultsUrl(executer: executer, testRunner: testRunner)
        for path in testResultsUrls.map(\.path) {
            guard path.hasPrefix(Path.base.rawValue) else { continue }
            _ = try executer.execute("rm -rf '\(path)' || true")
        }
    }
}
