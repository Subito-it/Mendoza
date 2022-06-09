//
//  Executer+Rsync.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/02/2019.
//

import Foundation

extension Executer {
    func rsync(sourcePath: String, destinationPath: String, include: [String] = [], exclude: [String] = [], on destinationNode: Node) throws { // swiftlint:disable:this function_default_parameter_at_end
        // https://gist.github.com/KartikTalwar/4393116
        let includes = include.map { "--include='\($0)'" }.joined(separator: " ")
        let excludes = exclude.map { "--exclude='\($0)'" }.joined(separator: " ")

        if AddressType(address: destinationNode.address) == .local {
            var rsyncCommand = ""

            if let remoteNode = (self as? RemoteExecuter)?.node {
                rsyncCommand = "rsync -ax \(includes) \(excludes) "

                guard let authentication = remoteNode.authentication else {
                    throw Error("Missing authentication for destination \(remoteNode.address)")
                }

                switch authentication {
                case let .agent(username):
                    rsyncCommand += "'\(username)@\(remoteNode.address):\(escapeSpaces(sourcePath))'"
                case let .key(username, _, _, passphrase):
                    guard passphrase == nil else { fatalError("passphare in key not supported yet") }
                    rsyncCommand += "'\(username)@\(remoteNode.address):\(escapeSpaces(sourcePath))'"
                case let .credentials(username, password):
                    logger?.addIgnoreList(password)
                    rsyncCommand = "sshpass -p '\(password)' " + rsyncCommand
                    rsyncCommand += "'\(username)@\(remoteNode.address):\(escapeSpaces(sourcePath))'"
                case .none:
                    rsyncCommand = #"rsync -ax \#(includes) \#(excludes) \#(escapeSpaces(sourcePath))"#
                }

                rsyncCommand += " \(escapeSpaces(destinationPath))"
            } else {
                rsyncCommand = #"rsync -ax \#(includes) \#(excludes) \#(escapeSpaces(sourcePath)) \#(escapeSpaces(destinationPath))"#
            }

            let destinationExecuter = try destinationNode.makeExecuter(logger: logger)
            _ = try destinationExecuter.execute("mkdir -p \(escapeSpaces(destinationPath))")
            _ = try destinationExecuter.execute(rsyncCommand)
        } else {
            guard let authentication = destinationNode.authentication else {
                throw Error("Missing authentication for destination \(destinationNode.address)")
            }

            var rsyncCommand = #"rsync -ax \#(includes) \#(excludes) -e "ssh -T -q -c aes128-gcm@openssh.com -o Compression=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -x" \#(escapeSpaces(sourcePath)) "#

            let username: String
            switch authentication {
            case let .agent(user):
                username = user
            case let .key(user, _, _, passphrase):
                guard passphrase == nil else { fatalError("passphare in key not supported yet") }
                username = user
            case let .credentials(user, password):
                logger?.addIgnoreList(password)
                rsyncCommand = "sshpass -p '\(password)' " + rsyncCommand
                username = user
            case .none:
                fatalError("Unexpected none authentication")
            }

            rsyncCommand += "'\(username)@\(destinationNode.address):\(escapeSpaces(destinationPath))'"

            let destinationExecuter = try destinationNode.makeExecuter(logger: logger)
            _ = try destinationExecuter.execute("mkdir -p \(escapeSpaces(destinationPath))")
            _ = try execute(rsyncCommand)
        }
    }

    private func escapeSpaces(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\ ")
    }
}
