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
        
    func path(buildNumber updatedbuildNumber: String) throws -> String {
        let xcodePaths = try executer.execute("find /Applications -maxdepth 1 -type d -name 'Xcode*.app'").split(separator: "\n")
        
        for xcodePath in xcodePaths {
            let infoPlistPath = xcodePath.appending("/Contents/version.plist")
            
            let appBuildNumber = try buildNumber(infoPlistPath: infoPlistPath)
            if appBuildNumber.lowercased() == updatedbuildNumber.lowercased() {
                return String(xcodePath)
            }
        }
        
        throw Error("Did not find Xcode version '\(updatedbuildNumber)' on '\(executer.address)'")
    }
        
    private func buildNumber(infoPlistPath: String) throws -> String {
        let version = try executer.execute("defaults read '\(infoPlistPath)' | grep \"ProductBuildVersion\"")
        let groups = try version.capturedGroups(withRegexString: " = (.*);")
        return groups.last ?? ""
    }
}
