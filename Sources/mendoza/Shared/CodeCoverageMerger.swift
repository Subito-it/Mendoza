//
//  CodeCoverageMerger.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/06/21.
//

import Foundation

class CodeCoverageMerger {
    private let executer: Executer
    private let searchPath: String
 
    init(executer: Executer, searchPath: String) {
        self.executer = executer
        self.searchPath = searchPath
    }
    
    func merge() throws -> String? {
        let coverageFiles = try findCoverageFilePaths(coveragePath: searchPath)
        
        guard coverageFiles.count > 0, let coverageUrl = URL(string: coverageFiles[0])?.deletingLastPathComponent() else {
            return nil
        }
        
        let coveragePath = coverageUrl.path
        let coverageDestinationPath = coverageUrl.appendingPathComponent("\(UUID().uuidString).profdata").path
        
        if coverageFiles.count == 1 {
            _ = try executer.execute("mv '\(coverageFiles[0])' '\(coverageDestinationPath)'")
        } else {
            // Workaround: as of Xcode 9.2 llvm-profdata isn't able to merge multiple big profdatas
            // merging in pairs seems to work though
            var mergeCommands = [String]()
            mergeCommands.append("mv '\(coverageFiles[0])' '\(coveragePath)/0.tmpprofdata'")
            
            for index in 1..<coverageFiles.count {
                mergeCommands.append("xcrun llvm-profdata merge '\(coveragePath)/\(index - 1).tmpprofdata' '\(coverageFiles[index])' -output '\(coveragePath)/\(index).tmpprofdata'")
                mergeCommands.append("rm '\(coverageFiles[index])'")
            }
            
            mergeCommands.append("mv '\(coveragePath)/\(coverageFiles.count - 1).tmpprofdata' '\(coverageDestinationPath)'")
            
            let filesToRemoveCommand = Array(0...coverageFiles.count - 2).map { "rm '\(coveragePath)/\($0).tmpprofdata'" }
            mergeCommands.append(contentsOf: filesToRemoveCommand)
            
            _ = try executer.execute(mergeCommands.joined(separator: "; "))
        }
        
        return coverageDestinationPath
    }
    
    private func findCoverageFilePaths(coveragePath: String) throws -> [String] {
        return try executer.execute("find '\(coveragePath)' -type f -name '*.profdata'").components(separatedBy: "\n")
    }
}
