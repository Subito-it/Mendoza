//
//  DiagnosticReporter.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Handles copying diagnostic and crash reports from simulators
class DiagnosticReporter {
    private let productNames: [String]

    init(productNames: [String]) {
        self.productNames = productNames
    }

    /// Copy diagnostic reports (crash logs) for the test runner
    func copyDiagnosticReports(executer: Executer, testRunner: TestRunner) throws {
        let testRunnerLogUrl = Path.logs.url.appendingPathComponent(testRunner.id)
        let destinationPath = testRunnerLogUrl.appendingPathComponent("DiagnosticReports").path

        _ = try executer.execute("mkdir -p '\(destinationPath)'")

        for productName in productNames {
            let sourcePath = "~/Library/Logs/DiagnosticReports/\(productName)_*"
            _ = try executer.execute("cp '\(sourcePath)' \(destinationPath) || true")
        }
    }
}
