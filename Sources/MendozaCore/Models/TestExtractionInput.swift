//
//  TestExtractionInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

public struct TestExtractionInput: Codable {
    let candidates: [URL]
    let device: Device
    let baseXCTestCaseClass: String
    let include: [String]
    let exclude: [String]
}

extension TestExtractionInput: DefaultInitializable {
    public static func defaultInit() -> TestExtractionInput {
        return TestExtractionInput(candidates: [], device: Device.defaultInit(), baseXCTestCaseClass: "XCTestCase", include: [], exclude: [])
    }
}
