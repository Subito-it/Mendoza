#!/usr/bin/swift

import Foundation

// struct XcodeBuildCommand: Codable {
//     var arguments: Array<String>
// }

// struct PreCompilationInput: Codable {
//     var xcodeBuildCommand: Array<String>
// }


// pluginData = "buildVariant:dev-stable,legData:leg/A/,filePath:xcconfig/MendozaSandboxUITests-Debug.xcconfig"

struct PreCompilationPlugin {
    func handle(_ input: PreCompilationInput, pluginData: String?) -> XcodeBuildCommand {
        var commands = input.xcodeBuildCommand

        guard 
            let data = pluginData else {
            print("Plugin data not provided using default commands")
            return XcodeBuildCommand(arguments: commands)
        }

        let configuration = data.toDictionary

        guard
            let buildVariant = configuration["buildVariant"],
            let xcconfig =  configuration["filePath"] else {
                let error = """
                Could not find plugin data falling back to default build command:
                
                Example of plugin data:
                buildVariant:dev-stable,legData:leg/A/,filePath:xcconfig/MendozaSandboxUITests-Debug.xcconfig
                """

                print(error)
                return XcodeBuildCommand(arguments: commands)
            }
        
        if let legData = configuration["legData"], !legData.isEmpty {
            commands.append("NAMESPACE_PREFIX='\(legData)'")
        }

        let updateBuildVariantCommand = "sed -i '' -e '/#include/s/dev-stable/\(buildVariant)/' \(xcconfig)"

        let result = Process().shell(updateBuildVariantCommand)

        guard result.status == 0 else {
            print("Failed update \(xcconfig) to \(buildVariant)")
            return XcodeBuildCommand(arguments: commands)
        }

        print(commands.map { $0.replacingOccurrences(of: "’", with: "'") }.joined(separator: " "))
        
        return XcodeBuildCommand(arguments: commands)
    }
}

extension String {
    var toDictionary: [String : String] {
        return  Dictionary(uniqueKeysWithValues: self.components(separatedBy: ",").map({ $0.components(separatedBy: ":") }).compactMap({ ($0[0], $0[1]) }))
    }
}

extension Process {
    @discardableResult
    func shell(_ command: String) -> (status: Int32, output: String) {
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
