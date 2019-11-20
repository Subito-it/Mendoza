//
//  ConfigurationInitializer.swift
//  Mendoza
//
//  Created by Tomas Camin on 08/01/2019.
//

import Bariloche
import Foundation
import KeychainAccess

struct ConfigurationInitializer {
    private let fileManager = FileManager.default
    
    func run() throws -> Void {
        let git = Git(executer: LocalExecuter())
        guard git.valid() else { throw Error("Git repo not inited or no refs found!") }
        #if !DEBUG
        guard git.clean() else { throw Error("Git repo is dirty!") }
        #endif
        
        print("Loading project...".blue)
        
        let gitStatus = try git.status()
        
        let baseUrl = gitStatus.url
        let currentUrl = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        let filePaths = try fileManager.contentsOfDirectory(at: currentUrl,
                                                            includingPropertiesForKeys: nil,
                                                            options: .skipsSubdirectoryDescendants)
        let workspaces = filePaths.filter { $0.path.hasSuffix(".xcworkspace") }
        let projects = filePaths.filter { $0.path.hasSuffix(".xcodeproj") }
        
        guard workspaces.count < 2 else { throw Error("Too many .xcworkspace found in folder!") }
        guard workspaces.count == 1 || projects.count < 2 else { throw Error("Too many .xcodeproj found in folder!") }
        guard let url = XcodeProject.projectUrl(from: workspaces.first) ?? projects.first else { throw Error("Failed to load .xcworkspace!") }
        guard let project = (try? XcodeProject(url: url)) else { throw Error("Failed to load .xcodeproj!") }
        
        let testingSchemes = project.testingSchemes().sorted { $0.name > $1.name }
        guard testingSchemes.count > 0 else { throw Error("No shared testing scheme found in \(url.path), does your UI Testing target have a dedicated scheme?1") }
        
        let selectedScheme = Bariloche.ask(title: "Select UI Testing scheme:", array: testingSchemes)
        
        let buildConfigurations = project.buildConfigurations().sorted()
        guard buildConfigurations.count > 0 else { throw Error("No build configuration found in \(url.path)!") }
        
        let selectedBuildConfiguration = Bariloche.ask(title: "Select build configuration used to run UI Tests:", array: buildConfigurations)

        let bundleIdentifiers = try project.getTargetsBundleIdentifiers(for: selectedScheme.value.name)
        let sdk = try project.getBuildSDK(for: selectedScheme.value.name)
        
        var storeAppleIdCredentials = false
        switch sdk {
        case .macos:
            break
        case .ios:
            let appleIdCredentials = Bariloche.ask(title: "Do you want required simulators to be installed automatically?", array: ["Yes, requires AppleID username/password (stored in Keychain)", "No"])
            storeAppleIdCredentials = appleIdCredentials.index == 0
            if storeAppleIdCredentials {
                let username: String = Bariloche.ask("\nAppleID username:".underline) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }
                let password: String = Bariloche.ask("\nAppleID password:".underline, secure: true) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }
                
                let keychain = KeychainAccess.Keychain(service: Environment.bundle)
                try! keychain.set(try! JSONEncoder().encode(Credentials(username: username, password: password)), key: "appleID")
            }
        }
        
        let nodes = try askNodes(sdk: sdk)
        
        let destinationNode: Node
        let resultDestinationNodeName = Bariloche.ask(title: "Please select which node should collect test results:", array: nodes.map { $0.name } + ["Other"])
        if resultDestinationNodeName.value == "Other" {
            destinationNode = try askNode(sdk: sdk)
        } else {
            destinationNode = nodes.first(where: { $0.name == resultDestinationNodeName.value})!
        }
        
        let resultDestinationPath: String = Bariloche.ask("\nPlease select at which path on `\(resultDestinationNodeName.value)` results should be saved".underline)
        let resultDestination = Configuration.ResultDestination(node: destinationNode, path: resultDestinationPath)
        
        let basePath = "\(baseUrl.path)/"
        let projectRelativePath = url.path.replacingOccurrences(of: basePath , with: "")
        let workspaceRelativePath = workspaces.first?.path.replacingOccurrences(of: basePath, with: "")
        
        let configuration = Configuration(projectPath: projectRelativePath,
                                          workspacePath: workspaceRelativePath,
                                          buildBundleIdentifier: bundleIdentifiers.build,
                                          testBundleIdentifier: bundleIdentifiers.test,
                                          scheme: selectedScheme.value.name,
                                          buildConfiguration: selectedBuildConfiguration.value,
                                          storeAppleIdCredentials: storeAppleIdCredentials,
                                          resultDestination: resultDestination,
                                          nodes: nodes,
                                          compilation: Configuration.Compilation(),
                                          sdk: sdk.rawValue)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(configuration)
        try data.write(to: currentUrl.appendingPathComponent(Environment.defaultConfigurationFilename))
        
        print("\n\n🎉 Done!".green)
    }
    
    func askNodes(sdk: XcodeProject.SDK) throws -> [Node] {
        print("\n* Configure nodes".magenta)
        
        var ret = [Node]()
        while (true) {
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
        
        let administratorPassword: String??
        let sshAuthentication: SSHAuthentication
        let concurrentTestRunners: Node.ConcurrentTestRunners
        var ramDiskSize: UInt? = nil
        
        let address = try askAddress()
        if ["127.0.0.1", "localhost"].contains(address) {
            let currentUser = try! LocalExecuter().execute("whoami")
            sshAuthentication = .none(username: currentUser)

            switch sdk {
            case .macos:
                administratorPassword = nil
                concurrentTestRunners = .manual(count: 1)
            case .ios:
                administratorPassword = askAdministratorPassword(username: sshAuthentication.username)
                concurrentTestRunners = askConcurrentSimulators()
            }
        } else {
            sshAuthentication = askSSHAuthentication()
            
            switch sdk {
            case .macos:
                concurrentTestRunners = .manual(count: 1)
                administratorPassword = nil
            case .ios:
                concurrentTestRunners = askConcurrentSimulators()
                
                switch sshAuthentication {
                case .credentials(_, let password):
                    administratorPassword = password
                default:
                    administratorPassword = askAdministratorPassword(username: sshAuthentication.username)
                }
            }
            
            Bariloche.ask("\nRam disk size in MB (useful for nodes without SSDs). Suggested 1024MB, not used if empty".underline) { (answer: String) in
                if answer.isEmpty {
                    ramDiskSize = nil
                } else if let size = UInt(answer) {
                    ramDiskSize = size
                } else {
                    throw Error("Invalid value")
                }
                
                return ""
            }
        }
        
        return Node(name: name,
                    address: address,
                    authentication: sshAuthentication,
                    administratorPassword: administratorPassword,
                    concurrentTestRunners: concurrentTestRunners,
                    ramDiskSizeMB: ramDiskSize)
    }
    
    func askAddress() throws -> String {
        let address: String = Bariloche.ask("\nAddress (ip or hostname):".underline) { answer in
            guard answer.count > 0 else {
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
            fatalError()
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
            let privateKeyPath: String = Bariloche.ask("Private key path (`~/.ssh/id_rsa` if empty):".underline)
            let publicKeyPath: String = Bariloche.ask("Public key path (not used if empty):".underline)
            let publicKeyPassphrase: String = Bariloche.ask("Public key passphrase (not used if empty):".underline)
            
            return .key(username: username,
                        privateKey: privateKeyPath.isEmpty ? "~/.ssh/id_rsa" : privateKeyPath,
                        publicKey: publicKeyPath.isEmpty ? nil : publicKeyPath,
                        passphrase: publicKeyPassphrase.isEmpty ? nil : publicKeyPassphrase)
        case 2:
            username = Bariloche.ask("\nUsername:".underline) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }
            
            return .agent(username: username)
        default:
            fatalError()
        }
    }
    
    func askAdministratorPassword(username: String) -> String?? {
        let storePassword = Bariloche.ask(title: "Store administrator username password? Required to perform actions such as simulator installation (e.g. `xcversion simulators --install='iOS X.X'`) ", array: ["Yes", "No"])
        switch storePassword.index {
        case 0:
            let password: String = Bariloche.ask("\nPassword for `\(username)`".underline, secure: true) { guard !$0.isEmpty else { throw Error("Invalid value") }; return $0 }
            return .some(password)
        default:
            return nil
        }
    }
}
