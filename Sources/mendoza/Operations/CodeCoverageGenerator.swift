//
//  File.swift
//  
//
//  Created by Tomas Camin on 17/10/24.
//

import Foundation

class CodeCoverageGenerator {
    private let configuration: Configuration
    private let baseUrl: URL

    init(configuration: Configuration, baseUrl: URL) {
        self.configuration = configuration
        self.baseUrl = baseUrl
    }

    func generateJsonCoverage(executer: Executer, coverageUrl: URL, summary: Bool, pathEquivalence: String?) throws -> URL {
        let executablePath = try findExecutablePath(executer: executer, buildBundleIdentifier: configuration.building.buildBundleIdentifier)
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

    func generateHtmlCoverage(executer: Executer, coverageUrl: URL, pathEquivalence: String?) throws -> URL {
        let executablePath = try findExecutablePath(executer: executer, buildBundleIdentifier: configuration.building.buildBundleIdentifier)
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

}
