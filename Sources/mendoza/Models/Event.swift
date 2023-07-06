//
//  Event.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

struct Event: Codable {
    let kind: Kind
    let info: [String: String]

    enum Kind: Int, Codable {
        case start, stop
        case startCompiling, stopCompiling
        case startTesting, stopTesting
        case error
    }
}

extension Event.Kind: CustomReflectable {
    var customMirror: Mirror {
        Mirror(self, children: ["hack": """
        enum Kind: Int, Codable {
            case start, stop
            case startCompiling, stopCompiling
            case startTesting, stopTesting
            case error
        }

        """])
    }
}

extension Event.Kind: DefaultInitializable {
    static func defaultInit() -> Event.Kind {
        .start
    }
}

extension Event: DefaultInitializable {
    static func defaultInit() -> Event {
        Event(kind: Event.Kind.defaultInit(), info: [:])
    }
}
