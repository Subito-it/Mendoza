//
//  TestCase.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

struct EstimatedTestCase: Codable, Hashable {
    let testCase: TestCase
    let estimatedDuration: TimeInterval?
}

extension EstimatedTestCase: DefaultInitializable {
    static func defaultInit() -> EstimatedTestCase {
        return EstimatedTestCase(testCase: TestCase.defaultInit(), estimatedDuration: nil)
    }
}
