//
//  LocalExecuter.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Foundation

final class LocalExecuter: Executer {
    var currentDirectoryPath: String? = nil
    var homePath: String = {
        return NSHomeDirectory()
    }()
    var address: String { return "localhost" }
    
    var logger: ExecuterLogger?
    
    private var running: Process?
    private let fileManager = FileManager.default
    
    init(currentDirectoryPath: String? = nil, logger: ExecuterLogger? = nil) {
        self.currentDirectoryPath = currentDirectoryPath
        self.logger = logger
    }
    
    func clone() throws -> LocalExecuter {
        return LocalExecuter(currentDirectoryPath: currentDirectoryPath, logger: nil)  // we cannot pass logger since it's not thread-safe
    }
    
    func execute(_ command: String, currentUrl: URL?, progress: ((String) -> Void)?, rethrow: (((status: Int32, output: String), Error) throws -> Void)?) throws -> String {
        return try capture(command, currentUrl: currentUrl, progress: progress, rethrow: rethrow).output
    }
    
    func capture(_ command: String, currentUrl: URL?, progress: ((String) -> Void)?, rethrow: (((status: Int32, output: String), Error) throws -> Void)?) throws -> (status: Int32, output: String) {
        let process = Process()
        defer { running = process }
        
        if let path = currentDirectoryPath {
            if #available(OSX 10.13, *) {
                process.currentDirectoryURL = URL(fileURLWithPath: path)
            } else {
                process.currentDirectoryPath = path
            }
        }

        return try process.capture(command, currentUrl: currentUrl, progress: progress, rethrow: rethrow, logger: logger)
    }
    
    func fileExists(atPath: String) throws -> Bool {
        return fileManager.fileExists(atPath: atPath)
    }
    
    // When it throws check that remotePath exists
    func download(remotePath: String, localUrl: URL) throws {
        let escapedRemotePath = expandingTildeInPath(remotePath)
        guard escapedRemotePath != localUrl.path else { return }
        
        logger?.log(command: "Copying `\(remotePath)` -> `\(localUrl.path)`")
        defer { logger?.log(output: "done", statusCode: 0) }
        
        try? fileManager.removeItem(at: localUrl)
        try fileManager.copyItem(atPath: escapedRemotePath, toPath: localUrl.path)
    }
    
    func upload(localUrl: URL, remotePath: String) throws {
        let escapedRemotePath = expandingTildeInPath(remotePath)
        guard escapedRemotePath != localUrl.path else { return }

        logger?.log(command: "Copying `\(localUrl.path)` -> `\(remotePath)`")
        defer { logger?.log(output: "done", statusCode: 0) }

        try? fileManager.removeItem(atPath: escapedRemotePath)
        try fileManager.copyItem(atPath: localUrl.path, toPath: escapedRemotePath)
    }
    
    func terminate() {
        running?.terminate()
    }
    
    func expandingTildeInPath(_ path: String) -> String {
        if #available(OSX 10.12, *) {
            return path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        } else {
            return path.replacingOccurrences(of: "~", with: URL(fileURLWithPath: NSHomeDirectory()).path)
        }
    }
}

private extension Process {
    @discardableResult
    func execute(_ command: String, currentUrl: URL? = nil, progress: ((String) -> Void)? = nil, rethrow: (((status: Int32, output: String), Error) throws -> Void)? = nil, logger: ExecuterLogger? = nil) throws -> String {
        let result = try capture(command, currentUrl: currentUrl, progress: progress, rethrow: rethrow, logger: logger)
        return result.output
    }
    
    func capture(_ command: String, currentUrl: URL? = nil, progress: ((String) -> Void)? = nil, rethrow: (((status: Int32, output: String), Error) throws -> Void)? = nil, logger: ExecuterLogger? = nil) throws -> (status: Int32, output: String) {
        let cmd = command.replacingOccurrences(of: "'~/", with: "~/'")
        
        logger?.log(command: cmd)
        
        let exports = (environment ?? [:]).map({ k, v in "; export \(k)=\(v)" }).joined(separator: "; ")
                
        arguments = ["-c", "source ~/.bash_profile; shopt -s huponexit; \(LocalExecuter.executablePathExport()) \(exports)\(cmd) 2>&1"]
        
        let pipe = Pipe()
        standardOutput = pipe
        standardError = pipe
        qualityOfService = .userInitiated
        
        do {
            if #available(OSX 10.13, *) {
                if let currentUrl = currentUrl {
                    currentDirectoryURL = currentUrl
                }
                
                executableURL = URL(fileURLWithPath: "/bin/bash")
                try run()
            } else {
                if let currentPath = currentUrl?.path {
                    currentDirectoryPath = currentPath
                }
                
                launchPath = "/bin/bash"
                guard FileManager.default.fileExists(atPath: "/bin/bash") else {
                    throw Error("/bin/bash does not exists")
                }
                
                launch()
            }
        } catch {
            fatalError(error.localizedDescription)
        }

        var outputData = Data()
        while isRunning {
            let data = pipe.fileHandleForReading.readData(ofLength: 512)
            guard data.count > 0 else { continue }

            outputData.append(data)
            progress?(String(decoding: data, as: UTF8.self))
        }
        outputData.append(pipe.fileHandleForReading.readDataToEndOfFile())
        
        pipe.fileHandleForReading.closeFile()
        
        var output = String(decoding: outputData, as: UTF8.self)
        output = output.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = (status: terminationStatus, output: output)
        
        logger?.log(output: result.output, statusCode: result.status)
        
        if terminationStatus != 0 {
            let redactedCmd = logger?.redact(cmd) ?? cmd
            let redactedOutput = logger?.redact(output) ?? output
            let originalError = Error("`\(redactedCmd)` failed with status code: \(result.status), got \(redactedOutput)")

            if let rethrow = rethrow {
                try rethrow(result, originalError)
                return result
            } else {
                throw originalError
            }
        }
        
        return result
    }
}
