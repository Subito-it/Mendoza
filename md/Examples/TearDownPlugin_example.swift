#!/usr/local/bin/swift-sh
// swiftlint:disable all

import Foundation

// class TestSessionResult: Codable {
//     var operationExecutionTime: Dictionary<String, Double>
//     var nodes: Dictionary<String, NodeStatistics>
//     var git: Optional<GitStatus>
//     var passedTests: Array<TestCaseResult>
//     var failedTests: Array<TestCaseResult>
//     var destination: Destination
//     var device: Device
//     var summaryPlistPath: Dictionary<String, String>
//     var date: String
//     var startTime: Double
// }
//
// struct GitStatus: Codable {
//     var url: URL
//     var branch: String
//     var lastMessage: String
//     var lastHash: String
// }
//
// class NodeStatistics: Codable {
//     var executionTime: Double
//     var totalTests: Int
// }
//
// enum Status: Int, Codable {
//     case passed, failed
// }
//
// class Destination: Codable {
//     var username: String
//     var address: String
//     var path: String
// }
//
// struct TestCaseResult: Codable {
//     var node: String
//     var summaryPlistPath: String
//     var suite: String
//     var name: String
//     var status: Status
//     var duration: Double
// }
//
// struct Device: Codable {
//     var name: String
//     var runtime: String
// }
//
struct TearDownPlugin {
    func handle(_ input: TestSessionResult, pluginData: String?) {
        let username = input.destination.username
        let address = input.destination.address
        
        for (plistPath, node) in input.summaryPlistPath {
            let customization = ["GroupingIdentifier": input.date,
                                 "BranchName": input.git?.branch ?? "",
                                 "CommitMessage": input.git?.lastMessage ?? "",
                                 "CommitHash": input.git?.lastHash ?? ""]
            
            let plistPath = "\(input.destination.path)/\(plistPath)".replacingOccurrences(of: "~/", with: "/Users/\(username)/")
            
            var commands = [String]()
            for (key, value) in customization {
                let escapedValue = value.replacingOccurrences(of: "'", with: "&quote;").replacingOccurrences(of: "\n", with: "<br />")
                commands.append("plutil -insert \(key) -string '\(escapedValue)' '\(plistPath)'")
            }
            
            let result = Process().capture("ssh \(username)@\(address) \"\(commands.joined(separator: "; "))\"")
            
            guard result.status == 0 else {
                print("Failed applying customization in \(plistPath) on node `\(node)`, got \(result.output)")
                return
            }
        }
         
        let totalExecutionTime = Int(CFAbsoluteTimeGetCurrent() - input.startTime)
        
        var fieldStrings = [(title: String, value: String)]()
        fieldStrings.append((title: "Total time", value: "\(totalExecutionTime) seconds"))
        if let testTime = input.operationExecutionTime["testRunnerOperation"] as? Double {
            fieldStrings.append((title: "Test time", value: "\(Int(testTime)) seconds"))
        }
        fieldStrings.append((title: "Successful tests", value: "\(input.passedTests.count)"))
        fieldStrings.append((title: "Failed tests", value: "\(input.failedTests.count)"))        
    }
    
    @discardableResult
    private func executeRequest(url: String) -> String {
        let url = URL(string: url)!
        
        var result: String = ""
        
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url) { data, _, error in
            defer { sem.signal() }
            guard error == nil, let data = data else {
                print("Failed fetching execution time\n\n")
                return
            }
            result = String(data: data, encoding: .utf8) ?? ""
        }.resume()
        guard sem.wait(timeout: .now() + 60.0) == .success else {
            print("Failed fetching execution time results\n\n")
            return ""
        }
        
        return result
    }
}

extension Process {
    @discardableResult
    func capture(_ command: String) -> (status: Int32, output: String) {
        arguments = ["-c", "source ~/.bash_profile; \(command)"]
        
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
