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
    
    var description: String { return "\(testCaseIdentifier) (\(duration) seconds)" }
    var testCaseIdentifier: String { "\(suite)/\(name)" }
}

extension TestCaseResult: DefaultInitializable {
    static func defaultInit() -> TestCaseResult {
        return TestCaseResult(node: "", xcResultPath: "", suite: "", name: "", status: .passed, duration: 0.0)
    }
}

extension TestCaseResult.Status: CustomReflectable {
    var customMirror: Mirror {
        return Mirror(self, children: ["hack": """
enum Status: Int, Codable {
    case passed, failed
}
            
"""]) }
}

extension TestCaseResult.Status: DefaultInitializable {
    static func defaultInit() -> TestCaseResult.Status {
        return .passed
    }
}
