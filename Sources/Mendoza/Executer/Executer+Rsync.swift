//
//  Executer+Rsync.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/02/2019.
//

import Foundation

extension Executer {
    func rsync(sourcePath: String, destinationPath: String, exclude: [String] = [], on destinationNode: Node) throws {
        // https://gist.github.com/KartikTalwar/4393116
        let excludes = exclude.map { "--exclude=\($0)" }.joined(separator: " ")

        if AddressType(address: destinationNode.address) == .local {
            var rsyncCommand = ""

            if let remoteNode = (self as? RemoteExecuter)?.node {
                rsyncCommand = "rsync -ax \(excludes) "

                guard let authentication = remoteNode.authentication else {
                    throw Error("Missing authentication for destination \(remoteNode.address)")
                }

                switch authentication {
                case let .agent(username):
                    rsyncCommand += "'\(username)@\(remoteNode.address):\(sourcePath)'"
                case let .key(username, _, _, passphrase):
                    guard passphrase == nil else { fatalError("passphare in key not supported yet") }
                    rsyncCommand += "'\(username)@\(remoteNode.address):\(sourcePath)'"
                case let .credentials(username, password):
                    logger?.addBlackList(password)
                    rsyncCommand = "sshpass -p '\(password)' " + rsyncCommand
                    rsyncCommand += "'\(username)@\(remoteNode.address):\(sourcePath)'"
                case .none:
                    rsyncCommand = #"rsync -ax \#(excludes) \#(sourcePath)"#
                }

                rsyncCommand += " \(destinationPath)"
            } else {
                rsyncCommand = #"rsync -ax \#(excludes) \#(sourcePath) \#(destinationPath)"#
            }

            let destinationExecuter = try destinationNode.makeExecuter(logger: logger)
            _ = try destinationExecuter.execute("mkdir -p \(destinationPath)")
            _ = try destinationExecuter.execute(rsyncCommand)
        } else {
            guard let authentication = destinationNode.authentication else {
                throw Error("Missing authentication for destination \(destinationNode.address)")
            }

            var rsyncCommand = #"rsync -ax \#(excludes) -e "ssh -T -q -c aes128-gcm@openssh.com -o Compression=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -x" \#(sourcePath) "#

            let username: String
            switch authentication {
            case let .agent(user):
                username = user
            case let .key(user, _, _, passphrase):
                guard passphrase == nil else { fatalError("passphare in key not supported yet") }
                username = user
            case let .credentials(user, password):
                logger?.addBlackList(password)
                rsyncCommand = "sshpass -p '\(password)' " + rsyncCommand
                username = user
            case .none:
                fatalError("Unexpected none authentication")
            }

            rsyncCommand += "'\(username)@\(destinationNode.address):\(destinationPath)'"

            let destinationExecuter = try destinationNode.makeExecuter(logger: logger)
            _ = try destinationExecuter.execute("mkdir -p \(destinationPath)")
            _ = try execute(rsyncCommand)
        }
    }
}
