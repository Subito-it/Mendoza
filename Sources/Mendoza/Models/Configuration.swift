//
//  Configuration.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation
import KeychainAccess

struct Configuration: Codable {
    let projectPath: String
    let workspacePath: String?
    let buildBundleIdentifier: String
    let testBundleIdentifier: String
    let scheme: String
    let baseXCTestCaseClass: String
    let buildConfiguration: String
    let storeAppleIdCredentials: Bool
    let resultDestination: ResultDestination
    let nodes: [Node]
    let compilation: Compilation
    let sdk: String
}

extension Configuration {
    struct Compilation: Codable {
        let buildSettings: String
        let onlyActiveArchitecture: String
        let architectures: String
        let useNewBuildSystem: String

        init(buildSettings: String = "GCC_OPTIMIZATION_LEVEL='s' SWIFT_OPTIMIZATION_LEVEL='-Osize'",
             onlyActiveArchitecture: String = "YES",
             architectures: String = "x86_64",
             useNewBuildSystem: String = "YES") {
            self.buildSettings = buildSettings
            self.onlyActiveArchitecture = onlyActiveArchitecture
            self.architectures = architectures
            self.useNewBuildSystem = useNewBuildSystem
        }
    }

    struct ResultDestination: Codable {
        let node: Node
        let path: String
    }
}

extension Configuration {
    func appleIdCredentials() -> Credentials? {
        let keychain = KeychainAccess.Keychain(service: Environment.bundle)

        guard let data = try? keychain.getData("appleID"),
            let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil
        }

        return credentials
    }
}
