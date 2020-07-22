//
//  RemoteExecuter.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Foundation
import Shout

final class RemoteExecuter: Executer {
    var currentDirectoryPath: String? {
        didSet {
            if connection != nil, oldValue != currentDirectoryPath {
                try? updateCurrentDirectoryPath()
            }
        }
    }

    var homePath: String {
        guard let username = node.authentication?.username else { fatalError("💣 Missing username") }
        return "/Users/\(username)"
    }

    var address: String { node.address }

    let node: Node
    var connection: Shout.SSH?
    var sftp: Shout.SFTP?
    var logger: ExecuterLogger?

    init(node: Node, currentDirectoryPath: String? = nil, logger: ExecuterLogger? = nil) {
        self.node = node
        self.currentDirectoryPath = currentDirectoryPath
        self.logger = logger
    }

    deinit {
        sftp?.shutdown()
    }

    func clone() throws -> RemoteExecuter {
        let executer = RemoteExecuter(node: node, currentDirectoryPath: currentDirectoryPath, logger: nil) // we cannot pass logger since it's not thread-safe
        try executer.connect()
        return executer
    }

    func connect() throws {
        guard let authentication = node.authentication else { throw Error("Missing authentication for node `\(node.address)`") }

        connection = try SSH(host: node.address)
        connection?.ptyType = .xterm

        switch authentication {
        case let .agent(username):
            try connection?.authenticateByAgent(username: username)
        case let .credentials(username, password):
            try connection?.authenticate(username: username, password: password)
        case let .key(username, privateKey, publicKey, passphrase):
            try connection?.authenticate(username: username, privateKey: privateKey, publicKey: publicKey, passphrase: passphrase)
        case .none:
            throw Error("No authentication method for node `\(node.address)`")
        }

        try updateCurrentDirectoryPath()
        try terminateProcessOnDisconnect()
    }

    func execute(_ command: String, currentUrl: URL?, progress: ((String) -> Void)? = nil, rethrow: (((status: Int32, output: String), Error) throws -> Void)?) throws -> String {
        try capture(command, currentUrl: currentUrl, progress: progress, rethrow: rethrow).output
    }

    func capture(_ command: String, currentUrl: URL?, progress: ((String) -> Void)? = nil, rethrow: (((status: Int32, output: String), Error) throws -> Void)?) throws -> (status: Int32, output: String) {
        guard let connection = connection else { fatalError("💣 Did not call connect()") }

        if let currentUrl = currentUrl {
            currentDirectoryPath = currentUrl.path
        }

        let cmd = command.replacingOccurrences(of: "'~/", with: "~/'")

        logger?.log(command: cmd)

        var result = (status: Int32(-999), output: "")
        do {
            result = try connection.capture("\(RemoteExecuter.executablePathExport()) \(cmd) 2>&1") { localProgress in
                progress?(localProgress)
            }

            var output = result.output
            output = output.replacingOccurrences(of: "\r\n", with: "\n")
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)

            logger?.log(output: output, statusCode: result.status)

            if result.status != 0 {
                let redactedCmd = logger?.redact(cmd) ?? cmd
                let originalError = Error("`\(redactedCmd)` failed with status code: \(result.status)")

                if let rethrow = rethrow {
                    try rethrow(result, originalError)
                    fatalError("💣 You should throw in rethrow!")
                } else {
                    throw originalError
                }
            }

            return (status: result.status, output: output)
        } catch {
            let redactedCmd = logger?.redact(cmd) ?? cmd
            let redactedError = logger?.redact("\(error)") ?? "\(error)"
            logger?.log(exception: "While running `\(redactedCmd)` got: \(redactedError)")

            if let rethrow = rethrow {
                try rethrow((status: -1, output: redactedError), Error("While running `\(redactedCmd)` got: \(redactedError)"))
                return result
            } else {
                throw error
            }
        }
    }

    func fileExists(atPath: String) throws -> Bool {
        try connection?.capture("ls '\(atPath)'").status == 0
    }

    func download(remotePath: String, localUrl: URL) throws {
        var sourcePath = remotePath
        if sourcePath.contains("~") {
            guard let username = node.authentication?.username else {
                throw Error("No username for tilde replacement!")
            }

            sourcePath = sourcePath.replacingOccurrences(of: "~", with: "/Users/\(username)")
        }

        logger?.log(command: "Copying `\(sourcePath)` -> `\(localUrl.path)`")
        defer { logger?.log(output: "done", statusCode: 0) }

        if sftp == nil { sftp = try connection?.openSftp() }
        try sftp?.download(remotePath: sourcePath, localUrl: localUrl)
    }

    func upload(localUrl: URL, remotePath: String) throws {
        var destinationPath = remotePath
        if destinationPath.contains("~") {
            guard let username = node.authentication?.username else {
                throw Error("No username for tilde replacement!")
            }

            destinationPath = destinationPath.replacingOccurrences(of: "~", with: "/Users/\(username)")
        }

        logger?.log(command: "Copying `\(localUrl.path)` -> `\(destinationPath)`")
        defer { logger?.log(output: "done", statusCode: 0) }

        if sftp == nil { sftp = try connection?.openSftp() }
        try sftp?.upload(localUrl: localUrl, remotePath: destinationPath)
    }

    func terminate() {
        try? connection?.terminate()
    }

    private func terminateProcessOnDisconnect() throws {
        try connection?.execute("shopt -s huponexit")
    }

    private func updateCurrentDirectoryPath() throws {
        if let path = currentDirectoryPath {
            try connection?.execute("cd \(path)")
        }
    }
}
