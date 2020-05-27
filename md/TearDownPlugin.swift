#!/usr/bin/swift

import Foundation

// class Destination: Codable {
//     var username: String
//     var address: String
//     var path: String
// }
//
// class NodeStatistics: Codable {
//     var executionTime: Double
//     var totalTests: Int
// }
//
// struct TestCaseResult: Codable {
//     var node: String
//     var xcResultPath: String
//     var suite: String
//     var name: String
//     var status: Status
//     var duration: Double
// }
//
// class TestSessionResult: Codable {
//     var operationExecutionTime: Dictionary<String, Double>
//     var nodes: Dictionary<String, NodeStatistics>
//     var git: Optional<GitStatus>
//     var passedTests: Array<TestCaseResult>
//     var failedTests: Array<TestCaseResult>
//     var destination: Destination
//     var device: Device
//     var xcResultPath: Dictionary<String, String>
//     var date: String
//     var startTime: Double
// }
//
// struct GitStatus: Codable {
//     var url: URL
//     var branch: String
//     var commitMessage: String
//     var commitHash: String
// }
//
// enum Status: Int, Codable {
//     case passed, failed
// }
//
// struct Device: Codable {
//     var name: String
//     var osVersion: String
//     var runtime: String
// }
//
struct TearDownPlugin {
    func handle(_ input: TestSessionResult, pluginData: String?) {
        // write your implementation here
    }
}
