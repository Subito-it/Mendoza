#!/usr/bin/swift

import Foundation

// struct TestExtractionInput: Codable {
//     var candidates: Array<URL>
//     var device: Device
//     var baseXCTestCaseClass: String
//     var include: Array<String>
//     var exclude: Array<String>
// }
//
// struct TestCase: Codable {
//     var name: String
//     var suite: String
//     var tags: Array<String>
//     var testCaseIDs: Array<String>
// }
//
// struct Device: Codable {
//     var name: String
//     var osVersion: String
//     var runtime: String
// }
//
struct TestExtractionPlugin {
    func handle(_ input: TestExtractionInput, pluginData: String?) -> Array<TestCase> {
        // write your implementation here
    }
}
