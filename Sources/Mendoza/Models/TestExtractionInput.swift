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
    let baseXCTestCaseClass: String
    let include: [String]
    let exclude: [String]
}

extension TestExtractionInput: DefaultInitializable {
    static func defaultInit() -> TestExtractionInput {
        TestExtractionInput(candidates: [], device: Device.defaultInit(), baseXCTestCaseClass: "XCTestCase", include: [], exclude: [])
    }
}
