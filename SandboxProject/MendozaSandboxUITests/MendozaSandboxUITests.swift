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
        testMethod(arg: ["T486"]) {
            XCTAssert(true)
        }
    }

    // @SmokeTest
    func testExampleTag() {
        tags(testTags: [
            .help,
            .regression,
        ])

        report(territory: [.uk], testCases: ["APP-T486", "APP-T486"]) {
            XCTAssert(true)
        }
    }

    func testExampleTag2() {
        tags(testTags: [
            .help,
        ])

        report(territory: [.uk], testCases: ["APP-T486", "APP-T486"]) {
            XCTAssert(true)
        }
    }

    func testExampleTag3() {
        tags(testTags: [
            .help,
        ])

        report(territory: [.uk], testCases: ["APP-T486", "APP-T486"]) {
            XCTAssert(true)
        }
    }

    func testExampleFail() {
        report(territory: [.uk], testCases: ["APP-T486d", "APP-T486d"]) {
            XCTAssert(false)
        }
    }
}

extension XCTestCase {
    func testMethod(arg _: [String], step: () -> Void) {
        XCTContext.runActivity(named: "Test run: ") { _ in
            step()
        }
    }

    func report(testCases _: [String], step: () -> Void) {
        XCTContext.runActivity(named: "Test run: ") { _ in
            step()
        }
    }

    func report(territory _: [Territory], testCases _: [String], step: () -> Void) {
        XCTContext.runActivity(named: "Test run: ") { _ in
            step()
        }
    }

    func tags(testTags: [TestTags]) {
        print(testTags)
    }

    enum TestTags {
        case help
        case regression
    }

    enum Territory {
        case uk
    }
}
