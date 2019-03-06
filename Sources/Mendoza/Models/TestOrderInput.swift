//
//  TestOrderInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

struct TestOrderInput: Codable {
    let tests: [TestCase]
    let simulatorCount: Int
    let device: Device
}

extension TestOrderInput: DefaultInitializable {
    static func defaultInit() -> TestOrderInput {
        return TestOrderInput(tests: [], simulatorCount: 0, device: Device.defaultInit())
    }
}
