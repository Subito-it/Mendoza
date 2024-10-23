//
//  ExecutablePath.swift
//  Mendoza
//
//  Created by Tomas Camin on 15/06/21.
//

import Foundation

func findExecutablePath(executer: Executer, buildBundleIdentifier: String) throws -> String {
    let plistPaths = try executer.execute("find '\(Path.build.rawValue)' -type f -name 'Info.plist' | grep -Ei '.app(/.*)?/Info.plist'").components(separatedBy: "\n")
    for plistPath in plistPaths {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else { continue }
        guard let plistInfo = try? PropertyListDecoder().decode(InfoPlist.self, from: data) else { continue }

        if plistInfo.bundleIdentifier == buildBundleIdentifier {
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
