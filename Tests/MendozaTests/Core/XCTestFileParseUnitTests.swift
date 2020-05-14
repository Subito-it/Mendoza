//
//  XCTestFileParseUnitTests.swift
//  MendozaTests
//
//  Created by Ashraf Ali on 20/05/2020.
//

import XCTest

class XCTestFileParseUnitTests: XCTestCase {
    func testExample() throws {
        //  TODO: Import MendozaCore
        let testData = """
        import XCTest

        class MendozaSandboxUITests: XCTestCase {
            override func setUp() {
                XCUIApplication().launch()
            }

            func testExamplePass() {
                XCTAssert(true)
            }

            // @SmokeTest
            func testExampleTag() {
                let testCaseIdentifier = ["SmokeTest"]
                XCTAssert(true)
            }

            func testExampleFail() {
                XCTAssert(false)
            }
        }
        """

        print(testData)
    }
}
