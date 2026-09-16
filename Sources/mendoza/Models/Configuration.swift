//
//  Configuration.swift
//
//
//  Created by tomas on 27/03/24.
//

import Foundation

struct Configuration: Codable {
    let building: Building
    let testing: Testing
    let device: Device?
    let plugins: Plugins?

    let resultDestination: ConfigurationResultDestination
    let nodes: [Node]

    let verbose: Bool
}

extension Configuration {
    struct Building: Codable {
        let projectPath: String // .xcworkspace or .xcodeproj
        let buildBundleIdentifier: String
        let testBundleIdentifier: String
        let scheme: String
        let buildConfiguration: String
        let sdk: String
        let settings: Settings // Using defaults should work for the time being
        let filePatterns: FilePatterns
        let xcodeBuildNumber: String?

        init(projectPath: String, buildBundleIdentifier: String, testBundleIdentifier: String, scheme: String, buildConfiguration: String, sdk: String, settings: Settings = Settings(), filePatterns: FilePatterns, xcodeBuildNumber: String?) {
            self.projectPath = projectPath
            self.buildBundleIdentifier = buildBundleIdentifier
            self.testBundleIdentifier = testBundleIdentifier
            self.scheme = scheme
            self.buildConfiguration = buildConfiguration
            self.sdk = sdk
            self.settings = settings
            self.filePatterns = filePatterns
            self.xcodeBuildNumber = xcodeBuildNumber
        }
    }

    struct Plugins: Codable {
        let data: String
        /// Where to keep each invocation's stdin envelope for replay. Defaults to the session
        /// logs, which are wiped when the next session starts.
        let replayPath: String?

        init(data: String = "", replayPath: String? = nil) {
            self.data = data
            self.replayPath = replayPath
        }
    }

    struct Testing: Codable {
        let maximumStdOutIdleTime: Int?
        let maximumTestExecutionTime: Int?
        let failingTestsRetryCount: Int?
        let xcresultBlobThresholdKB: Int?
        let killSimulatorProcesses: Bool
        let alwaysRebootSimulators: Bool
        let autodeleteSlowDevices: Bool
        let codeCoveragePathEquivalence: String?
        let extractIndividualTestCoverage: Bool
        let extractTestCoveredFiles: Bool
        let clearDerivedDataOnCompilationFailure: Bool
        let skipResultMerge: Bool
        let disabledSimulatorServices: [String]
        let collectTestDiagnosticsOnFailure: Bool
        /// Nil preserves decoding and encoding of configurations written before batching existed.
        var testBatchSize: Int? = nil

        var effectiveTestBatchSize: Int { testBatchSize ?? 1 }

        func validateBatchSize() throws {
            guard (1 ... 2).contains(effectiveTestBatchSize) else {
                throw Error("test_batch_size must be 1 or 2")
            }
        }
    }
}

extension Configuration.Building {
    struct Settings: Codable {
        let buildSettings: String
        let onlyActiveArchitecture: String
        let architectures: String

        /// - Note: `buildSettings` is empty by default so that the project's own build configuration is
        ///         honoured. These end up on xcodebuild's command line, which outranks every xcconfig,
        ///         target and configuration value in the project.
        init(buildSettings: String = "", onlyActiveArchitecture: Bool = true, architectures: String = "arm64") {
            self.buildSettings = buildSettings
            self.onlyActiveArchitecture = onlyActiveArchitecture ? "YES" : "NO"
            self.architectures = architectures
        }
    }
}

struct ConfigurationResultDestination: Codable {
    let node: Node
    let path: String
}
