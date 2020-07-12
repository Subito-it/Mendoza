//
//  ProcessExtension.swift
//  MendozaSharedLibrary
//
//  Created by Ashraf Ali on 12/07/2020.
//

import Foundation

public extension Process {
    @discardableResult
    func shell(command: String) -> (status: Int32, output: String) {
        arguments = ["-c", "\(command)"]

        let stdout = Pipe()
        standardOutput = stdout
        qualityOfService = .userInitiated

        launchPath = "/bin/bash"
        guard FileManager.default.fileExists(atPath: "/bin/bash") else {
            fatalError("/bin/bash does not exists")
        }

        launch()

        waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: String.Encoding.utf8) ?? ""
        return (terminationStatus, result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
    }
}
