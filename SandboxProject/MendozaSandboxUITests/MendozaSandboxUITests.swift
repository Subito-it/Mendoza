//
//  MendozaSandboxUITests.swift
//  MendozaSandboxUITests
//
//  Created by tomas on 07/07/2019.
//  Copyright © 2019 tomas. All rights reserved.
//

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

