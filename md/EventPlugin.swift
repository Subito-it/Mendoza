#!/usr/bin/swift

import Foundation

// enum Kind: Int, Codable {
//     case start, stop
//     case startCompiling, stopCompiling
//     case startTesting, stopTesting
//     case error
// }
//
// struct Device: Codable {
//     var name: String
//     var osVersion: String
//     var runtime: String
// }
//
// struct EventPluginInput: Codable {
//     var event: Event
//     var device: Device
// }
//
// struct Event: Codable {
//     var kind: Kind
//     var info: Dictionary<String, String>
// }
//
struct EventPlugin {
    func handle(_ input: EventPluginInput, pluginData: String?) {
        // write your implementation here
    }
}
