//
//  ConfigurationValidator.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

class XcodeVersion {
    private let executer: Executer
    
    init(executer: Executer) {
        self.executer = executer
    }
        
    func setCurrent(buildNumber updatedbuildNumber: String, administratorPassword password: String) throws {
        guard try current().lowercased() != updatedbuildNumber.lowercased() else { return }
        
        let xcodePaths = try executer.execute("find /Applications -maxdepth 1 -type d -name 'Xcode*.app'").split(separator: "\n")
        
        for xcodePath in xcodePaths {
            let infoPlistPath = xcodePath.appending("/Contents/version.plist")
            
            let appBuildNumber = try buildNumber(infoPlistPath: infoPlistPath)
            if appBuildNumber.lowercased() == updatedbuildNumber.lowercased() {
                _ = try executer.execute("echo '\(password)' | sudo -S xcode-select -s '\(xcodePath)'")
                return
            }
        }
        
        throw Error("Did not find Xcode version '\(updatedbuildNumber)' on '\(executer.address)'")
    }
    
    private func current() throws -> String {
        let currentPath = try executer.execute("xcode-select -p")
        
        guard currentPath.hasSuffix("Contents/Developer") else {
            throw Error("Unexpected Xcode.app path '\(currentPath)' on '\(executer.address)'")
        }
        
        let infoPlistPath = currentPath.replacingOccurrences(of: "Contents/Developer", with: "Contents/version.plist")

        return try buildNumber(infoPlistPath: infoPlistPath)
    }
    
    private func buildNumber(infoPlistPath: String) throws -> String {
        let version = try executer.execute("defaults read '\(infoPlistPath)' | grep \"ProductBuildVersion\"")
        let groups = try version.capturedGroups(withRegexString: " = (.*);")
        return groups.last ?? ""
    }
}
