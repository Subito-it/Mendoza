//
//  ConfigurationAuthenticationUpdater.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Bariloche
import Foundation
import KeychainAccess

struct ConfigurationAuthenticationUpdater {
    private let configurationUrl: URL
    private let configuration: Configuration

    init(configurationUrl: URL) throws {
        self.configurationUrl = configurationUrl
        let configurationData = try Data(contentsOf: configurationUrl)
        configuration = try JSONDecoder().decode(Configuration.self, from: configurationData)
    }

    func run() throws {
        let validator = ConfigurationValidator(configuration: configuration)
        let initializer = ConfigurationInitializer()

        var modified = false

        var lastNode: Node?

        var updatedNodes = [Node]()
        for node in configuration.nodes {
            var authentication = node.authentication
            var password = node.administratorPassword

            if !validator.validAuthentication(node: node) {
                print("\n* Authentication for `\(node.address)`".magenta)

                switch AddressType(node: node) {
                case .local:
                    let currentUser = try LocalExecuter().execute("whoami")
                    authentication = .none(username: currentUser)
                case .remote:
                    if let lastNode = lastNode, AddressType(node: lastNode) == .remote {
                        if Bariloche.ask(title: "Use the same credentials provided for `\(lastNode.name)`?", array: ["Yes", "No"]).index == 0 {
                            let updatedNode = Node(name: node.name, address: node.address, authentication: lastNode.authentication, administratorPassword: lastNode.administratorPassword, concurrentTestRunners: node.concurrentTestRunners, ramDiskSizeMB: node.ramDiskSizeMB)
                            updatedNodes.append(updatedNode)
                            continue
                        }
                    }

                    authentication = initializer.askSSHAuthentication()
                }

                modified = true
            }

            if !validator.validAdministratorPassword(node: node), let username = authentication?.username {
                print("\n* Password for user \(username) on `\(node.address)`".magenta)
                password = initializer.askAdministratorPassword(username: username)
                modified = true
            }

            lastNode = Node(name: node.name, address: node.address, authentication: authentication, administratorPassword: password, concurrentTestRunners: node.concurrentTestRunners, ramDiskSizeMB: node.ramDiskSizeMB)
            updatedNodes.append(lastNode!) // swiftlint:disable:this force_unwrapping
        }

        let updatedConfiguration = Configuration(projectPath: configuration.projectPath, workspacePath: configuration.workspacePath, buildBundleIdentifier: configuration.buildBundleIdentifier, testBundleIdentifier: configuration.testBundleIdentifier, scheme: configuration.scheme, buildConfiguration: configuration.buildConfiguration, resultDestination: configuration.resultDestination, nodes: updatedNodes, compilation: configuration.compilation, sdk: configuration.sdk, device: configuration.device, xcresultBlobThresholdKB: configuration.xcresultBlobThresholdKB)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let configurationData = try encoder.encode(updatedConfiguration)
        try configurationData.write(to: configurationUrl)

        if !modified {
            print("\n\n🎉 Valid configuration!".green)
        }
    }
}
