//
//  CodeCoverageCollectionOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class CodeCoverageCollectionOperation: BaseOperation<Void> {
    private lazy var executer: Executer = {
        return makeLocalExecuter()
    }()
    private let configuration: Configuration
    private let baseUrl: URL
    private let timestamp: String
    
    init(configuration: Configuration, baseUrl: URL, timestamp: String) {
        self.configuration = configuration
        self.baseUrl = baseUrl
        self.timestamp = timestamp
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            let destinationNode = configuration.resultDestination.node
            
            let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
            let destinationExecuter = try destinationNode.makeExecuter(logger: logger)
            
            let resultPath = "\(configuration.resultDestination.path)/\(timestamp)"
            let destinationPath = "\(resultPath)/coverage"

            let coveragePaths = try findCoverageFilePaths(executer: destinationExecuter, resultPath: resultPath)
            let mergedPath = try mergeCoverageFiles(executer: destinationExecuter, destinationPath: destinationPath, paths: coveragePaths)
            
            let localCoverageUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).profdata")
            try destinationExecuter.download(remotePath: mergedPath, localUrl: localCoverageUrl)
            
            let jsonCoverageUrl = try generateJsonCoverage(coverageUrl: localCoverageUrl)
            
            try crushJsonCoverage(jsonCoverageUrl, basePath: baseUrl.path)
                        
            try destinationExecuter.upload(localUrl: jsonCoverageUrl, remotePath: "\(destinationPath)/\(Environment.coverageFilename)")

            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }
    
    private func findCoverageFilePaths(executer: Executer, resultPath: String) throws -> [String] {
        return try executer.execute("find '\(resultPath)' -type f -name 'Coverage.profdata'").components(separatedBy: "\n")
    }
    
    private func mergeCoverageFiles(executer: Executer, destinationPath: String, paths: [String]) throws -> String {
        guard paths.count > 0 else { throw Error("No code coverage file paths to merge") }
        
        let coverageDestinationPath = "\(destinationPath)/\(UUID().uuidString).profdata"
        
        _ = try executer.execute("mkdir -p \(destinationPath)")
        if paths.count == 1 {
            _ = try executer.execute("cp '\(paths[0])' '\(coverageDestinationPath)'")
        } else {
            // Workaround: as of Xcode 9.2 llvm-profdata isn't able to merge multiple big profdatas
            // merging in pairs seems to work though
            _ = try executer.execute("cp '\(paths[0])' '\(destinationPath)/0.tmpprofdata'")
            for index in 1..<paths.count {
                _ = try executer.execute("xcrun llvm-profdata merge '\(destinationPath)/\(index - 1).tmpprofdata' '\(paths[index])' -output '\(destinationPath)/\(index).tmpprofdata'")
            }
            _ = try executer.execute("mv '\(destinationPath)/\(paths.count - 1).tmpprofdata' '\(coverageDestinationPath)'")
            
            let filesToRemoveCommand = Array(0...paths.count - 2).map { "rm '\(destinationPath)/\($0).tmpprofdata'" }.joined(separator: "; ")
            _ = try executer.execute(filesToRemoveCommand)
        }
        
        return coverageDestinationPath
    }
    
    private func generateJsonCoverage(coverageUrl: URL) throws -> URL {
        let executablePath = try findExecutablePath()
        let jsonCoverageUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")
        _ = try executer.execute("xcrun llvm-cov export -instr-profile \(coverageUrl.path) \(executablePath) > \(jsonCoverageUrl.path)")

        return jsonCoverageUrl
    }
    
    private func findExecutablePath() throws -> String {
        let plistPaths = try executer.execute("find '\(Path.build.rawValue)' -type f -name 'Info.plist' | grep -Ei '.app(/.*)?/Info.plist'").components(separatedBy: "\n")
        for plistPath in plistPaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else { continue }
            guard let plistInfo = try? PropertyListDecoder().decode(InfoPlist.self, from: data) else { continue }
            
            if plistInfo.bundleIdentifier == configuration.buildBundleIdentifier {
                let executablePath: String
                if plistInfo.supportedPlatforms?.contains("MacOSX") == true {
                    executablePath = URL(fileURLWithPath: plistPath).deletingLastPathComponent().appendingPathComponent("MacOS").appendingPathComponent(plistInfo.executableName).path
                } else {
                    executablePath = URL(fileURLWithPath: plistPath).deletingLastPathComponent().appendingPathComponent(plistInfo.executableName).path
                }
                return executablePath
            }
        }

        throw Error("Failed finding executable path")
    }

    private func crushJsonCoverage(_ url: URL, basePath: String) throws {
        let content = try String(contentsOf: url)
        
        // Remove basePath can reduce filesize by more that 15%
        let crushedContent = content.replacingOccurrences(of: "\(basePath)/", with: "")
        try crushedContent.data(using: .utf8)?.write(to: url)
    }

    override func cancel() {
        if isExecuting {
            executer.terminate()
        }
        super.cancel()
    }
}
