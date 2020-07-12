//
//  Event.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

public struct Event: Codable {
    let kind: Kind
    let info: [String: String]
    let values: [String: [String]]

    enum Kind: Int, Codable {
        case start, stop
        case startCompiling, stopCompiling
        case startTesting, stopTesting
        case testSuiteStarted, testSuiteFinished
        case testCaseStarted, testCaseFinished
        case testPassed, testFailed, testCrashed
        case error
    }
}

extension Event.Kind: CustomReflectable {
    var customMirror: Mirror {
        let kind = """
        enum Kind: Int, Codable {
            case start, stop
            case startCompiling, stopCompiling
            case startTesting, stopTesting
            case testSuiteStarted, testSuiteFinished
            case testCaseStarted, testCaseFinished
            case testPassed, testFailed, testCrashed
            case error
        }

        """

        return Mirror(self, children: ["hack": kind])
    }
}

extension Event.Kind: DefaultInitializable {
    static func defaultInit() -> Event.Kind {
        .start
    }
}

extension Event: DefaultInitializable {
    public static func defaultInit() -> Event {
        return Event(kind: Event.Kind.defaultInit(), info: [:], values: [:])
    }
}
