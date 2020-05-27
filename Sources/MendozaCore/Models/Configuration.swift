//
//  Configuration.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation
import KeychainAccess

public struct Configuration: Codable {
    public let projectPath: String
    public let workspacePath: String?
    public let buildBundleIdentifier: String
    public let testBundleIdentifier: String
    public let scheme: String
    public let baseXCTestCaseClass: String
    public let buildConfiguration: String
    public let storeAppleIdCredentials: Bool
    public let resultDestination: ResultDestination
    public let nodes: [Node]
    public let compilation: Compilation
    public let sdk: String

    public init(
        projectPath: String,
        workspacePath: String?,
        buildBundleIdentifier: String,
        testBundleIdentifier: String,
        scheme: String,
        baseXCTestCaseClass: String,
        buildConfiguration: String,
        storeAppleIdCredentials: Bool,
        resultDestination: ResultDestination,
        nodes: [Node],
        compilation: Compilation,
        sdk: String
    ) {
        self.projectPath = projectPath
        self.workspacePath = workspacePath
        self.buildBundleIdentifier = buildBundleIdentifier
        self.testBundleIdentifier = testBundleIdentifier
        self.scheme = scheme
        self.baseXCTestCaseClass = baseXCTestCaseClass
        self.buildConfiguration = buildConfiguration
        self.storeAppleIdCredentials = storeAppleIdCredentials
        self.resultDestination = resultDestination
        self.nodes = nodes
        self.compilation = compilation
        self.sdk = sdk
    }
}

extension Configuration {
    public struct Compilation: Codable {
        let buildSettings: String
        let onlyActiveArchitecture: String
        let architectures: String
        let useNewBuildSystem: String

        public init(
            buildSettings: String = "GCC_OPTIMIZATION_LEVEL='s' SWIFT_OPTIMIZATION_LEVEL='-Osize'",
            onlyActiveArchitecture: String = "YES",
            architectures: String = "x86_64",
            useNewBuildSystem: String = "YES"
        ) {
            self.buildSettings = buildSettings
            self.onlyActiveArchitecture = onlyActiveArchitecture
            self.architectures = architectures
            self.useNewBuildSystem = useNewBuildSystem
        }
    }

    public struct ResultDestination: Codable {
        let node: Node
        let path: String

        public init(node: Node, path: String) {
            self.node = node
            self.path = path
        }
    }
}

extension Configuration {
    public func appleIdCredentials() -> Credentials? {
        let keychain = KeychainAccess.Keychain(service: Environment.bundle)

        guard let data = try? keychain.getData("appleID"),
            let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil
        }

        return credentials
    }
}
