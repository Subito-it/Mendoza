//
//  ModernConfiguration.swift
//
//
//  Created by tomas on 27/03/24.
//

import Foundation

struct ModernConfiguration: Codable {
    let building: Building
    let testing: Testing
    let device: Device?
    let plugins: Plugins?

    let resultDestination: ConfigurationResultDestination
    let nodes: [Node]

    let verbose: Bool
}

extension ModernConfiguration {
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
        let debug: Bool

        init(data: String = "", debug: Bool = false) {
            self.data = data
            self.debug = debug
        }
    }

    struct Testing: Codable {
        let maximumStdOutIdleTime: Int?
        let maximumTestExecutionTime: Int?
        let failingTestsRetryCount: Int?
        let xcresultBlobThresholdKB: Int?
        let killSimulatorProcesses: Bool
        let autodeleteSlowDevices: Bool
        let codeCoveragePathEquivalence: String?
        let clearDerivedDataOnCompilationFailure: Bool
        let skipResultMerge: Bool
        let skipSimulatorsSetup: Bool
    }
}

extension ModernConfiguration.Building {
    struct Settings: Codable {
        let buildSettings: String
        let onlyActiveArchitecture: String
        let architectures: String

        init(buildSettings: String = "GCC_OPTIMIZATION_LEVEL='s' SWIFT_OPTIMIZATION_LEVEL='-Osize'", onlyActiveArchitecture: Bool = true, architectures: String = "arm64") {
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
