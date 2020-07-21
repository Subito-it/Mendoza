//
//  TestCaseResult.swift
//  Mendoza
//
//  Created by Tomas Camin on 24/02/2019.
//

import Foundation

public struct TestCaseResult: Codable, CustomStringConvertible, Hashable {
    public enum Status: Int, Codable {
        case passed, failed
    }

    public let node: String
    public let xcResultPath: String
    public let suite: String
    public let name: String
    public let status: Status
    public let duration: Double
    public let testCaseIDs: [String]
    public let testTags: [String]
    public let message: String

    public var description: String { "\(testCaseIdentifier) (\(duration) seconds)" }
    public var testCaseIdentifier: String { "\(suite)/\(name)" }

    public static func == (lhs: TestCaseResult, rhs: TestCaseResult) -> Bool {
        return lhs.testCaseIdentifier == rhs.testCaseIdentifier
    }

    public var didTestPass: Bool {
        switch status {
        case .passed: return true
        default: return false
        }
    }
}

extension TestCaseResult: DefaultInitializable {
    public static func defaultInit() -> TestCaseResult {
        return TestCaseResult(node: "", xcResultPath: "", suite: "", name: "", status: .passed, duration: 0.0, testCaseIDs: [], testTags: [], message: "")
    }
}

extension TestCaseResult.Status: CustomReflectable {
    public var customMirror: Mirror {
        let status = """
        enum Status: Int, Codable {
            case passed, failed
        }

        """

        return Mirror(self, children: ["hack": status])
    }
}

extension TestCaseResult.Status: DefaultInitializable {
    public static func defaultInit() -> TestCaseResult.Status {
        .passed
    }
}
