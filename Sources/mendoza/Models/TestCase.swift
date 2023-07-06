//
//  TestCase.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

struct TestCase: Codable, Hashable {
    let name: String
    let suite: String

    var testIdentifier: String { "\(suite)/\(name)" }
}

extension TestCase: DefaultInitializable {
    static func defaultInit() -> TestCase {
        TestCase(name: "", suite: "")
    }
}

extension TestCase: CustomStringConvertible {
    var description: String { suite + " " + name }
}
