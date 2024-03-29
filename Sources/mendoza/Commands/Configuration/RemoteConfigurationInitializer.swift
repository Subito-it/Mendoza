//
//  RemoteConfigurationInitializer.swift
//  Mendoza
//
//  Created by Tomas Camin on 08/01/2019.
//

import Bariloche
import Foundation
import KeychainAccess

struct RemoteConfigurationInitializer {
    private let fileManager = FileManager.default

    func run() throws {
        let currentUrl = URL(fileURLWithPath: fileManager.currentDirectoryPath)

        let sdk = askProjectSdk()

        let nodes = try askNodes(sdk: sdk)

        let destinationNode: Node
        let resultDestinationNodeName = Bariloche.ask(title: "Please select which node should collect test results:", array: nodes.map(\.name) + ["Other"])
        if resultDestinationNodeName.value == "Other" {
            destinationNode = try askNode(sdk: sdk)
        } else {
            destinationNode = nodes.first(where: { $0.name == resultDestinationNodeName.value })! // swiftlint:disable:this force_unwrapping
        }

        let resultDestinationPath: String = Bariloche.ask("\nPlease select at which path on `\(resultDestinationNodeName.value)` results should be saved".underline)
        let resultDestination = ConfigurationResultDestination(node: destinationNode, path: resultDestinationPath)

        let configuration = RemoteConfiguration(resultDestination: resultDestination, nodes: nodes)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(configuration)
        try data.write(to: currentUrl.appendingPathComponent(Environment.defaultConfigurationFilename))

        print("\n\n🎉 Done!".green)
    }

    func askNodes(sdk: XcodeProject.SDK) throws -> [Node] {
        print("\n* Configure nodes".magenta)

        var ret = [Node]()
        while true {
            let node = try askNode(sdk: sdk)

            guard Bariloche.ask(title: "Add node?\n".underline + node.description.lightGreen, array: ["Yes", "No"]).index == 0 else {
                continue
            }

            ret.append(node)

            guard Bariloche.ask(title: "\nSetup additional node?", array: ["Yes", "No"]).index == 0 else {
                return ret
            }
        }
    }

    func askNode(sdk: XcodeProject.SDK) throws -> Node {
        let name: String = Bariloche.ask("\nName (identifier that will be used in logging):".underline) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }

        let sshAuthentication: SSHAuthentication
        let concurrentTestRunners: Node.ConcurrentTestRunners

        let address = try askAddress()
        if ["127.0.0.1", "localhost"].contains(address) {
            let currentUser = try LocalExecuter().execute("whoami")
            sshAuthentication = .none(username: currentUser)

            switch sdk {
            case .macos:
                concurrentTestRunners = .manual(count: 1)
            case .ios:
                concurrentTestRunners = askConcurrentSimulators()
            }
        } else {
            sshAuthentication = askSSHAuthentication()

            switch sdk {
            case .macos:
                concurrentTestRunners = .manual(count: 1)
            case .ios:
                concurrentTestRunners = askConcurrentSimulators()
            }
        }

        return Node(name: name,
                    address: address,
                    authentication: sshAuthentication,
                    concurrentTestRunners: concurrentTestRunners)
    }

    func askAddress() throws -> String {
        let address: String = Bariloche.ask("\nAddress (ip or hostname):".underline) { answer in
            guard !answer.isEmpty else {
                throw Error("Invalid address")
            }

            _ = try LocalExecuter().execute("ping -W 1000 -c 1 \(answer)") { _, _ in throw Error("Node address unreachable") }

            return answer
        }

        return address
    }

    func askConcurrentSimulators() -> Node.ConcurrentTestRunners {
        let result = Bariloche.ask(title: "How many simulators should run concurrently?", array: ["Autodetect", "Manual"])
        switch result.index {
        case 0:
            return .autodetect
        case 1:
            let count: UInt = Bariloche.ask("\nConcurrent simulators:".underline)
            return .manual(count: count)
        default:
            fatalError("Unexpected case \(result.index)")
        }
    }

    func askProjectSdk() -> XcodeProject.SDK {
        let result = Bariloche.ask(title: "Will you run tests on macOS?", array: ["Yes", "No"])
        switch result.index {
        case 0:
            return .macos
        case 1:
            return .ios
        default:
            fatalError("Unexpected case \(result.index)")
        }
    }

    func askSSHAuthentication() -> SSHAuthentication {
        let authenticationType = Bariloche.ask(title: "SSH authentication method", array: ["Credentials (username and password)", "SSH keys", "SSH Agent"])

        let username: String
        switch authenticationType.index {
        case 0:
            username = Bariloche.ask("\nUsername:".underline) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }
            let password: String = Bariloche.ask("\nPassword:".underline)

            return .credentials(username: username, password: password)
        case 1:
            username = Bariloche.ask("\nUsername:".underline) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }
            let privateKeyPath: String = Bariloche.ask("Private key path (`~/.ssh/id_ed25519` if empty):".underline)
            let publicKeyPath: String = Bariloche.ask("Public key path (not used if empty):".underline)
            let publicKeyPassphrase: String = Bariloche.ask("Public key passphrase (not used if empty):".underline)

            return .key(username: username,
                        privateKey: privateKeyPath.isEmpty ? "~/.ssh/id_ed25519" : privateKeyPath,
                        publicKey: publicKeyPath.isEmpty ? nil : publicKeyPath,
                        passphrase: publicKeyPassphrase.isEmpty ? nil : publicKeyPassphrase)
        case 2:
            username = Bariloche.ask("\nUsername:".underline) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }

            return .agent(username: username)
        default:
            fatalError("Unexpected case \(authenticationType.index)")
        }
    }
}
