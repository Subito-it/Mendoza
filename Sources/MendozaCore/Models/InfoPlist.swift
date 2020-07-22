//
//  InfoPlist.swift
//  Mendoza
//
//  Created by Tomas Camin on 26/02/2019.
//

import Foundation

struct InfoPlist: Codable {
    let bundleIdentifier: String
    let executableName: String
    let supportedPlatforms: [String]?

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "CFBundleIdentifier"
        case executableName = "CFBundleExecutable"
        case supportedPlatforms = "CFBundleSupportedPlatforms"
    }
}
