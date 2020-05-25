#!/usr/bin/swift

import Foundation

// struct TestCase: Codable {
//     var name: String
//     var suite: String
//     var tags: Array<String>
//     var testCaseIDs: Array<String>
// }
// 
// struct TestOrderInput: Codable {
//     var tests: Array<TestCase>
//     var device: Device
// }
// 
// struct Device: Codable {
//     var name: String
//     var osVersion: String
//     var runtime: String
// }
// 
struct TestSortingPlugin {
    func handle(_ input: TestOrderInput, pluginData: String?) -> Array<TestCase> {
        return input.tests.sorted(by: { $0.name > $1.name })
    }
}
