//
//  TestOrderInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

public struct TestOrderInput: Codable {
    let tests: [TestCase]
    let device: Device
}

extension TestOrderInput: DefaultInitializable {
    public static func defaultInit() -> TestOrderInput {
        return TestOrderInput(tests: [], device: Device.defaultInit())
    }
}
