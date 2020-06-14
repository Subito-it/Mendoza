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

    let node: String
    let xcResultPath: String
    let suite: String
    let name: String
    let status: Status
    let duration: Double
    let testCaseIDs: [String]
    let testTags: [String]

    var description: String { "\(testCaseIdentifier) (\(duration) seconds)" }
    var testCaseIdentifier: String { "\(suite)/\(name)" }

    static func == (lhs: TestCaseResult, rhs: TestCaseResult) -> Bool {
        return lhs.testCaseIdentifier == rhs.testCaseIdentifier
    }
}

extension TestCaseResult: DefaultInitializable {
    static func defaultInit() -> TestCaseResult {
        return TestCaseResult(node: "", xcResultPath: "", suite: "", name: "", status: .passed, duration: 0.0, testCaseIDs: [], testTags: [])
    }
}

extension TestCaseResult.Status: CustomReflectable {
    var customMirror: Mirror {
        let status = """
        enum Status: Int, Codable {
            case passed, failed
        }

        """

        return Mirror(self, children: ["hack": status])
    }
}

extension TestCaseResult.Status: DefaultInitializable {
    static func defaultInit() -> TestCaseResult.Status {
        .passed
    }
}
