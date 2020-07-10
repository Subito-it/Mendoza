//
//  ConfigurationValidator.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

class ConfigurationValidator {
    var loggers: Set<ExecuterLogger> = []

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func validate() throws {
        try validateNodes()
        try validateReachability()
        try validateConnections()
        try validateAuthentication()
        try validateAdministratorPassword()
        try validateAppleIdCredentials()
    }

    func validateNodes() throws {
        for node in configuration.nodes {
            guard configuration.nodes.filter({ $0.name == node.name }).count == 1 else {
                throw Error("Node name `\(node.name)` repeated more than once in configuration")
            }

            guard configuration.nodes.filter({ $0.address == node.address }).count == 1 else {
                throw Error("Node address `\(node.address)` repeated more than once in configuration")
            }
        }
    }

    func validAuthentication(node: Node) -> Bool {
        node.authentication != nil
    }

    func validAdministratorPassword(node: Node) -> Bool {
        do {
            guard let passwordBox = node.administratorPassword else { return true }
            guard let password = passwordBox else { return false }

            let logger = ExecuterLogger(name: "\(type(of: self))", address: node.address)
            let executer = try node.makeExecuter(logger: logger)
            loggers.insert(logger)

            executer.logger?.addBlackList(password)
            _ = try executer.execute("echo '\(password)' | sudo -S -v")
        } catch {
            return false
        }

        return true
    }

    private func validateReachability() throws {
        let remoteNodes = configuration.nodes.remote()

        let logger = ExecuterLogger(name: "\(type(of: self))", address: "localhost")
        let localExecuter = LocalExecuter(logger: logger)
        loggers.insert(logger)

        var unreachableNodes = [Node]()
        for node in remoteNodes {
            do {
                _ = try localExecuter.execute("ping -W 1000 -c 1 \(node.address)")
            } catch {
                unreachableNodes.append(node)
            }
        }

        guard unreachableNodes.isEmpty else {
            throw Error("The following nodes are unreachable:\n\(unreachableNodes.map { "- \($0.address)" }.joined(separator: "\n"))", logger: logger)
        }
    }

    private func validateConnections() throws {
        let remoteNodes = configuration.nodes.remote()

        do {
            let logger: (Node) -> ExecuterLogger = { ExecuterLogger(name: "\(type(of: self))", address: $0.address) }
            let poolSources = remoteNodes.map { ConnectionPool<Void>.Source(node: $0, logger: logger($0)) }
            let pool = ConnectionPool(sources: poolSources)

            let poolLoggers = Set(poolSources.compactMap { $0.logger })
            loggers = loggers.union(poolLoggers)

            try pool.execute { executer, _ in
                _ = try executer.execute("ls")
            }
        } catch {
            throw Error("Invalid credentials for connection. Configuration file needs to be updated! Please run `\(ConfigurationRootCommand().name!) \(ConfigurationAuthententicationUpdateCommand().name!)` command. Got \(error)".red)
        }
    }

    private func validateAppleIdCredentials() throws {
        guard configuration.storeAppleIdCredentials else { return }

        guard let credentials = configuration.appleIdCredentials() else {
            throw Error("Missing apple ID credentials. Configuration file needs to be updated! Please run `\(ConfigurationRootCommand().name!) \(ConfigurationAuthententicationUpdateCommand().name!)` command".red)
        }

        // TODO: validate that apple credentials are valid
        _ = credentials
    }

    private func validateAuthentication() throws {
        guard configuration.nodes.allSatisfy({ validAuthentication(node: $0) }) else {
            throw Error("Invalid credentials found. Configuration file needs to be updated! Please run `\(ConfigurationRootCommand().name!) \(ConfigurationAuthententicationUpdateCommand().name!)` command".red)
        }
    }

    private func validateAdministratorPassword() throws {
        guard configuration.nodes.allSatisfy({ validAdministratorPassword(node: $0) }) else {
            throw Error("Invalid administrator password found. Configuration file needs to be updated! Please run `\(ConfigurationRootCommand().name!) \(ConfigurationAuthententicationUpdateCommand().name!)` command".red)
        }
    }
}
