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
        let excludes = exclude.map({ "--exclude=\($0)" }).joined(separator: " ")
        var rsyncCommand = #"rsync -ax \#(excludes) -e "ssh -T -q -c aes128-gcm@openssh.com -o Compression=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -x" \#(sourcePath) "#

        guard let authentication = destinationNode.authentication else {
            throw Error("Missing authentication for destination \(destinationNode.address)")
        }
        
        let username: String
        switch authentication {
        case .agent(let user):
            username = user
        case .key(let user, _, _, let passphrase):
            guard passphrase == nil else { fatalError("passphare in key not supported yet") }
            username = user
        case .credentials(let user, let password):
            logger?.addBlackList(password)
            rsyncCommand = "sshpass -p '\(password)'" + rsyncCommand
            username = user
        case .none:
            fatalError("Unexpected localhost destination")
        }
        
        rsyncCommand += "\(username)@\(destinationNode.address):\(destinationPath)"
        
        let destinationExecuter = try destinationNode.makeExecuter(logger: logger)
        _ = try destinationExecuter.execute("mkdir -p \(destinationPath)")
        
        _ = try execute(rsyncCommand)
    }
}
