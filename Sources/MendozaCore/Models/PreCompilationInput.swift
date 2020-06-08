//
//  PreCompilationInput.swift
//  MendozaCore
//
//  Created by Ashraf Ali on 08/06/2020.
//

import Foundation

public struct PreCompilationInput: Codable {
    public let xcodeBuildCommand: [String]

    public init(xcodeBuildCommand: [String]) {
        self.xcodeBuildCommand = xcodeBuildCommand.map { $0.replacingOccurrences(of: "’", with: "'") }
    }
}

extension PreCompilationInput: DefaultInitializable {
    public static func defaultInit() -> PreCompilationInput {
        return PreCompilationInput(xcodeBuildCommand: [])
    }
}
