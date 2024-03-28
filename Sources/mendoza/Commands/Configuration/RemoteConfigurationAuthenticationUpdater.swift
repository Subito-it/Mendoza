//
//  ConfigurationAuthenticationUpdater.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Bariloche
import Foundation
import KeychainAccess

struct RemoteConfigurationAuthenticationUpdater {
    private let configurationUrl: URL
    private let configuration: RemoteConfiguration

    init(configurationUrl: URL) throws {
        self.configurationUrl = configurationUrl
        let configurationData = try Data(contentsOf: configurationUrl)
        configuration = try JSONDecoder().decode(RemoteConfiguration.self, from: configurationData)
    }

    func run() throws {
        let validator = RemoteConfigurationValidator(nodes: [])
        let initializer = RemoteConfigurationInitializer()

        var modified = false

        var lastNode: Node?

        var updatedNodes = [Node]()
        for node in configuration.nodes {
            var authentication = node.authentication

            if !validator.validAuthentication(node: node) {
                print("\n* Authentication for `\(node.address)`".magenta)

                switch AddressType(node: node) {
                case .local:
                    let currentUser = try LocalExecuter().execute("whoami")
                    authentication = .none(username: currentUser)
                case .remote:
                    if let lastNode = lastNode, AddressType(node: lastNode) == .remote {
                        if Bariloche.ask(title: "Use the same credentials provided for `\(lastNode.name)`?", array: ["Yes", "No"]).index == 0 {
                            let updatedNode = Node(name: node.name, address: node.address, authentication: lastNode.authentication, concurrentTestRunners: node.concurrentTestRunners)
                            updatedNodes.append(updatedNode)
                            continue
                        }
                    }

                    authentication = initializer.askSSHAuthentication()
                }

                modified = true
            }

            lastNode = Node(name: node.name, address: node.address, authentication: authentication, concurrentTestRunners: node.concurrentTestRunners)
            updatedNodes.append(lastNode!) // swiftlint:disable:this force_unwrapping
        }

        let updatedConfiguration = RemoteConfiguration(resultDestination: configuration.resultDestination, nodes: updatedNodes)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let configurationData = try encoder.encode(updatedConfiguration)
        try configurationData.write(to: configurationUrl)

        if !modified {
            print("\n\n🎉 Valid configuration!".green)
        }
    }
}
