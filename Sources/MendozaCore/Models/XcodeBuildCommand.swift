//
//  XcodeBuildCommand.swift
//  MendozaCore
//
//  Created by Ashraf Ali on 08/06/2020.
//

import Foundation

public struct XcodeBuildCommand: Codable, Hashable {
    public let arguments: [String]

    public var output: String { arguments.joined(separator: " ").replacingOccurrences(of: "’", with: "'") }

    public init(arguments: [String]) {
        self.arguments = arguments.map { $0.replacingOccurrences(of: "’", with: "'") }
    }
}

extension XcodeBuildCommand: DefaultInitializable {
    public static func defaultInit() -> XcodeBuildCommand {
        return XcodeBuildCommand(arguments: [])
    }
}
