@testable import mendoza
import XCTest

final class XcodebuildOutputParserTests: XCTestCase {
    private let parser = XcodebuildOutputParser(testTarget: "MyAppUITests")

    func testTestStartIsParsed() {
        let line = "Test Case '-[MyAppUITests.LoginTests testLogin]' started"

        XCTAssertEqual(parser.event(for: line), .testStart(TestCase(name: "testLogin", suite: "LoginTests")))
    }

    func testTestStartWithSpaceInTargetName() {
        let spacedParser = XcodebuildOutputParser(testTarget: "My App UITests")
        let line = "Test Case '-[My_App_UITests.LoginTests testLogin]' started"

        XCTAssertEqual(spacedParser.event(for: line), .testStart(TestCase(name: "testLogin", suite: "LoginTests")))
    }

    func testTestPassed() {
        let line = "Test Case '-[MyAppUITests.LoginTests testLogin]' passed (12.34 seconds)"

        XCTAssertEqual(parser.event(for: line), .testPassed(duration: 12.34))
    }

    func testSkippedIsTreatedAsPassed() {
        let line = "Test Case '-[MyAppUITests.LoginTests testLogin]' skipped (0.01 seconds)"

        XCTAssertEqual(parser.event(for: line), .testPassed(duration: 0.01))
    }

    func testTestFailed() {
        let line = "Test Case '-[MyAppUITests.LoginTests testLogin]' failed (5.0 seconds)"

        XCTAssertEqual(parser.event(for: line), .testFailed(duration: 5.0))
    }

    func testTestTimedOut() {
        let line = "Test Case '-[MyAppUITests.LoginTests testLogin]' exceeded execution time allowance"

        XCTAssertEqual(parser.event(for: line), .testTimedOut)
    }

    func testNoSpaceOnDevice() {
        let line = ##"Error Domain=NSPOSIXErrorDomain Code=28 "No space left on device""##

        XCTAssertEqual(parser.event(for: line), .noSpaceOnDevice)
    }

    func testCrashMarker1() {
        let line = "Restarting after unexpected exit or crash in LoginTests/testLogin()"

        XCTAssertEqual(parser.event(for: line), .testCrashed)
    }

    func testCrashMarker2() {
        let line = "    testLogin() encountered an error (Crash: MyApp (1234)"

        XCTAssertEqual(parser.event(for: line), .testCrashed)
    }

    func testCrashMarker3() {
        let line = "Checking for crash reports corresponding to unexpected termination of MyApp"

        XCTAssertEqual(parser.event(for: line), .testCrashed)
    }

    func testCrashMarker4() {
        let line = "Restarting after unexpected exit, crash, or test timeout in LoginTests.testLogin()"

        XCTAssertEqual(parser.event(for: line), .testCrashed)
    }

    func testRunnerExitedIsTreatedAsFailure() {
        let line = "    testLogin() encountered an error (Test runner exited before starting test execution)"

        XCTAssertEqual(parser.event(for: line), .testFailed(duration: -1))
    }

    func testTestingFailedMarker() {
        XCTAssertEqual(parser.event(for: "Testing failed:"), .testFailed(duration: -1))
    }

    func testUnrelatedLineReturnsNil() {
        XCTAssertNil(parser.event(for: "Compiling MyApp.swift"))
        XCTAssertNil(parser.event(for: ""))
    }

    func testLineFromDifferentTargetIsIgnored() {
        let line = "Test Case '-[OtherTarget.LoginTests testLogin]' passed (1.0 seconds)"

        XCTAssertNil(parser.event(for: line))
    }
}
