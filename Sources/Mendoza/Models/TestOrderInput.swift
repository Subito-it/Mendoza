//
//  TestOrderInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

struct TestOrderInput: Codable {
    let tests: [TestCase]
    let device: Device
}

extension TestOrderInput: DefaultInitializable {
    static func defaultInit() -> TestOrderInput {
        TestOrderInput(tests: [], device: Device.defaultInit())
    }
}
