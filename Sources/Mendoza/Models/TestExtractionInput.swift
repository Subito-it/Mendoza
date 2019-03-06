//
//  TestExtractionInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

struct TestExtractionInput: Codable {
    let candidates: [URL]
    let device: Device
}

extension TestExtractionInput: DefaultInitializable {
    static func defaultInit() -> TestExtractionInput {
        return TestExtractionInput(candidates: [], device: Device.defaultInit())
    }
}
