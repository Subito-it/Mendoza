//
//  TestCaseResult.swift
//  Mendoza
//
//  Created by Tomas Camin on 24/02/2019.
//

import Foundation

struct TestCaseResult: Codable, CustomStringConvertible, Hashable {
    enum Status: Int, Codable {
        case passed, failed
    }

    var duration: TimeInterval { endInterval - startInterval }

    var node: String
    var runnerName: String
    var runnerIdentifier: String
    var xcResultPath: String
    var suite: String
    var name: String
    var status: Status
    var startInterval: TimeInterval
    var endInterval: TimeInterval

    var description: String { "\(testCaseIdentifier) (\(Int(endInterval - startInterval)) seconds)" }
    var testCaseIdentifier: String { "\(suite)/\(name)" }
}

extension TestCaseResult: DefaultInitializable {
    static func defaultInit() -> TestCaseResult {
        TestCaseResult(node: "", runnerName: "", runnerIdentifier: "", xcResultPath: "", suite: "", name: "", status: .passed, startInterval: 0.0, endInterval: 0.0)
    }
}

extension TestCaseResult.Status: CustomReflectable {
    var customMirror: Mirror {
        Mirror(self, children: ["hack": """
        enum Status: Int, Codable {
            case passed, failed
        }

        """])
    }
}

extension TestCaseResult.Status: DefaultInitializable {
    static func defaultInit() -> TestCaseResult.Status {
        .passed
    }
}
