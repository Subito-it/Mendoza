#!/usr/bin/swift

import Foundation

// struct XcodeBuildCommand: Codable {
//     var arguments: Array<String>
// }
// 
// struct PreCompilationInput: Codable {
//     var xcodeBuildCommand: Array<String>
// }
// 
struct PreCompilationPlugin {
    func handle(_ input: PreCompilationInput, pluginData: String?) -> XcodeBuildCommand {
        // write your implementation here
        let commands = input.xcodeBuildCommand

        print("Test")
        print(commands)
        

        return XcodeBuildCommand(arguments: commands)
    }
}
