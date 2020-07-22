//
//  TestTool.swift
//  MendozaTests
//
//  Created by Ashraf Ali on 30/06/2020.
//

import XCTest
@testable import MendozaCore

class TestTool: XCTestCase {
    func testExample() throws {
        let includePatternField = sandboxLocation
        let excludePatternField = ""

        let includeTestField = "help"
        let excludeTestField = ""

        let device = Device(name: "iPhone 11 Pro Max", osVersion: "13.2.2")
        let timeout = 120
        let filePatterns = FilePatterns(commaSeparatedIncludePattern: includePatternField, commaSeparatedExcludePattern: excludePatternField)
        let testFilters = TestFilters(commaSeparatedIncludePattern: includeTestField, commaSeparatedExcludePattern: excludeTestField)
        let testForStabilityCount = 0
        let failingTestsRetryCount = 0

        let sut = try Test(
            configurationFile: "mendoza.json",
            device: device,
            runHeadless: false,
            filePatterns: filePatterns,
            testFilters: testFilters,
            testTimeoutSeconds: timeout,
            testForStabilityCount: testForStabilityCount,
            failingTestsRetryCount: failingTestsRetryCount,
            dispatchOnLocalHost: false,
            pluginData: nil,
            debugPlugins: false,
            verbose: true,
            directory: sandboxLocation
        )

        try sut.run()
    }
}
