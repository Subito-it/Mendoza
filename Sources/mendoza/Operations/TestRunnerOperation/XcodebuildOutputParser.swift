//
//  XcodebuildOutputParser.swift
//  Mendoza
//
//  Created by tomas.camin on 01/06/22.
//

import Foundation

enum XcodebuildLineEvent: Equatable {
    case testStart(TestCase)
    case testPassed(duration: Double)
    case testFailed(duration: Double)
    case testCrashed
    case noSpaceOnDevice
    case testTimedOut

    var isTestPassed: Bool {
        switch self { case .testPassed: return true; default: return false }
    } // swiftlint:disable:this switch_case_alignment
    var isTestCrashed: Bool {
        switch self { case .testCrashed: return true; default: return false }
    } // swiftlint:disable:this switch_case_alignment
}

/// Classifies a single line of `xcodebuild` console output into a `XcodebuildLineEvent`.
///
/// Kept free of any I/O or execution state so the regex matching can be unit tested in isolation.
struct XcodebuildOutputParser {
    private let testTarget: String

    init(testTarget: String) {
        self.testTarget = testTarget.replacingOccurrences(of: " ", with: "_")
    }

    func event(for line: String) -> XcodebuildLineEvent? {
        let testResultCrashMarker1 = #"Restarting after unexpected exit or crash in (.*)/(.*)\(\)"#
        let testResultCrashMarker2 = #"\s+(.*)\(\) encountered an error \(Crash:"#
        let testResultCrashMarker3 = #"Checking for crash reports corresponding to unexpected termination of"#
        let testResultCrashMarker4 = #"Restarting after unexpected exit, crash, or test timeout in (.*)\.(.*)\(\)"#
        let testResultTimeoutMarker1 = #"\s+(.*)\(\) encountered an error \(Test runner exited"# // Should be caused by the force reset of simulator
        let testResultFailureMarker1 = #"^(Testing failed:)$"#

        let startRegex = #"Test Case '-\[\#(testTarget)\.(.*)\]' started"#

        if line.contains(##"Code=28 "No space left on device""##) {
            return .noSpaceOnDevice
        }

        if let tests = try? line.capturedGroups(withRegexString: startRegex), tests.count == 1 {
            let testCaseName = tests[0].components(separatedBy: " ").last ?? ""
            let testCaseSuite = tests[0].components(separatedBy: " ").first ?? ""

            return .testStart(TestCase(name: testCaseName, suite: testCaseSuite))
        }

        let passFailRegex = #"Test Case '-\[\#(testTarget)\.(.*)\]' (passed|failed|skipped) \((.*) seconds\)"#
        if let tests = try? line.capturedGroups(withRegexString: passFailRegex), tests.count == 3 {
            let duration = Double(tests[2]) ?? -1

            if ["skipped", "passed"].contains(tests[1]) {
                return .testPassed(duration: duration)
            } else if tests[1] == "failed" {
                return .testFailed(duration: duration)
            } else {
                return nil
            }
        }

        let timeoutRegex = #"Test Case '-\[\#(testTarget)\.(.*)\]' exceeded execution time allowance"#
        if let tests = try? line.capturedGroups(withRegexString: timeoutRegex), tests.count == 1 {
            return .testTimedOut
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker1), tests.count == 2 {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker2), tests.count == 1 {
            return .testCrashed
        }

        if line.contains(testResultCrashMarker3) {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultCrashMarker4), tests.count == 2 {
            return .testCrashed
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultTimeoutMarker1), tests.count == 1 {
            return .testFailed(duration: -1)
        }

        if let tests = try? line.capturedGroups(withRegexString: testResultFailureMarker1), tests.count == 1 {
            return .testFailed(duration: -1)
        }

        return nil
    }
}
