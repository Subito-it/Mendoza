//
//  RemoteConfigurationValidator.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

class RemoteConfigurationValidator {
    var loggers: Set<ExecuterLogger> = []

    private let nodes: [Node]

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    func validate() throws {
        try validateNodes()
        try validateReachability()
        try validateConnections()
        try validateAuthentication()
    }

    func validateNodes() throws {
        for node in nodes {
            guard nodes.filter({ $0.name == node.name }).count == 1 else {
                throw Error("Node name `\(node.name)` repeated more than once in configuration")
            }

            guard nodes.filter({ $0.address == node.address }).count == 1 else {
                throw Error("Node address `\(node.address)` repeated more than once in configuration")
            }
        }
    }

    func validAuthentication(node: Node) -> Bool {
        guard AddressType(node: node) == .remote else { return true }

        return node.authentication != nil
    }

    private func validateReachability() throws {
        let remoteNodes = nodes.remote()

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
        let remoteNodes = nodes.remote()

        do {
            let logger: (Node) -> ExecuterLogger = { ExecuterLogger(name: "\(type(of: self))", address: $0.address) }
            let poolSources = remoteNodes.map { ConnectionPool<Void>.Source(node: $0, logger: logger($0), environment: [:]) }
            let pool = ConnectionPool(sources: poolSources)

            let poolLoggers = Set(poolSources.compactMap(\.logger))
            loggers = loggers.union(poolLoggers)

            try pool.execute { executer, _ in
                _ = try executer.execute("ls")
            }
        } catch {
            throw Error("Invalid credentials for connection. Configuration file needs to be updated! Please run `\(RemoteConfigurationRootCommand().name!) \(RemoteConfigurationAuthententicationUpdateCommand().name!)` command. Got \(error)".red) // swiftlint:disable:this force_unwrapping
        }
    }

    private func validateAuthentication() throws {
        guard nodes.allSatisfy({ validAuthentication(node: $0) }) else {
            throw Error("Invalid credentials found. Configuration file needs to be updated! Please run `\(RemoteConfigurationRootCommand().name!) \(RemoteConfigurationAuthententicationUpdateCommand().name!)` command".red) // swiftlint:disable:this force_unwrapping
        }
    }
}
