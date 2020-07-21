//
//  Junit.swift
//  MendozaCore
//
//  Created by Ashraf Ali on 17/06/2020.
//

import Foundation

public struct JunitTestCaseFailure {
    public let reason: String // "Test failed because of blah"
    public let fileLine: String // File.swift:42

    public init(reason: String, fileLine: String) {
        self.reason = reason
        self.fileLine = fileLine
    }
}

public struct JunitTestCase {
    public let className: String // FunctionalTests.AbuseTests_91953
    public let name: String // test, testDataSet0
    public let timestamp: TimeInterval // when the test was executed, current timezone will be used
    public let time: TimeInterval // Time taken (in seconds) to execute the tests in the suite
    public let hostname: String
    public let isFailure: Bool
    public let failures: [JunitTestCaseFailure]

    public init(
        className: String,
        name: String,
        timestamp: TimeInterval,
        time: TimeInterval,
        hostname: String,
        isFailure: Bool,
        failures: [JunitTestCaseFailure]
    ) {
        self.className = className
        self.name = name
        self.timestamp = timestamp
        self.time = time
        self.hostname = hostname
        self.isFailure = isFailure
        self.failures = failures
    }
}

public final class JunitGenerator {
    private let testCaseResult: [TestCaseResult]
    private let junitTestCases: [JunitTestCase]
    private let dateFormatter = DateFormatter()

    public init(testCaseResult: [TestCaseResult]) {
        self.testCaseResult = testCaseResult
        junitTestCases = testCaseResult.map { (testCase) -> JunitTestCase in
            JunitTestCase(
                className: testCase.suite,
                name: testCase.name,
                timestamp: testCase.duration,
                time: testCase.duration,
                hostname: "",
                isFailure: !testCase.didTestPass,
                failures: [JunitTestCaseFailure(reason: testCase.message, fileLine: "")]
            )
        }
    }

    public func writeReport(path: URL) throws {
        let report = try generateReport()
        try report.write(to: path, atomically: true, encoding: .utf8)
    }

    func generateReport() throws -> String {
        var classNameToTestCases = [String: [JunitTestCase]]()
        var totalTestCount: Int = 0
        var totalFailureCount: Int = 0

        junitTestCases.forEach { (testCase: JunitTestCase) in
            let className = testCase.className
            totalTestCount += 1

            if testCase.isFailure {
                totalFailureCount += 1
            }

            if var cases = classNameToTestCases[className] {
                cases.append(testCase)
                classNameToTestCases[className] = cases
            } else {
                classNameToTestCases[className] = [testCase]
            }
        }

        let xmlTestSuites = XMLElement(name: "testsuites")
        try xmlTestSuites.addAttribute(withName: "name", stringValue: "xctest")
        try xmlTestSuites.addAttribute(withName: "tests", stringValue: "\(totalTestCount)")
        try xmlTestSuites.addAttribute(withName: "failures", stringValue: "\(totalFailureCount)")

        try classNameToTestCases.forEach { (className: String, testCases: [JunitTestCase]) in
            var testSuiteTestCount: Int = 0
            var testSuiteFailureCount: Int = 0

            let xmlTestSuite = XMLElement(name: "testsuite")
            try xmlTestSuite.addAttribute(withName: "name", stringValue: "\(className)")

            try testCases.forEach { (testCase: JunitTestCase) in
                let xmlTestCase = XMLElement(name: "testcase")

                testSuiteTestCount += 1
                if testCase.isFailure {
                    testSuiteFailureCount += 1
                    if testCase.failures.isEmpty {
                        xmlTestCase.addChild(
                            try self.xmlFailure(
                                JunitTestCaseFailure(reason: "No test failure has been captured", fileLine: "Unknown:??")
                            )
                        )
                    } else {
                        try testCase.failures.forEach { failure in
                            xmlTestCase.addChild(try self.xmlFailure(failure))
                        }
                    }
                }

                try xmlTestCase.addAttribute(withName: "classname", stringValue: "\(className)")
                try xmlTestCase.addAttribute(withName: "name", stringValue: "\(testCase.name)")
                // TODO: Fix timestamp
                try xmlTestCase.addAttribute(withName: "timestamp", stringValue: "\(dateFormatter.iso8601(date: Date()))")
                try xmlTestCase.addAttribute(withName: "time", stringValue: "\(testCase.time)")
                try xmlTestCase.addAttribute(withName: "hostname", stringValue: "\(testCase.hostname)")
                xmlTestSuite.addChild(xmlTestCase)
            }

            try xmlTestSuite.addAttribute(withName: "tests", stringValue: "\(testSuiteTestCount)")
            try xmlTestSuite.addAttribute(withName: "failures", stringValue: "\(testSuiteFailureCount)")
            xmlTestSuites.addChild(xmlTestSuite)
        }

        let xml = XMLDocument()
        xml.setRootElement(xmlTestSuites)
        xml.version = "1.0"
        xml.characterEncoding = "UTF-8"

        return xml.xmlString(options: [.nodePrettyPrint]) + "\n"
    }

    private func xmlFailure(_ failure: JunitTestCaseFailure) throws -> XMLElement {
        let xmlFailure = XMLElement(name: "failure", stringValue: failure.fileLine)
        let message = failure.reason.components(separatedBy: CharacterSet.controlCharacters).joined(separator: "")
        try xmlFailure.addAttribute(withName: "message", stringValue: message)
        return xmlFailure
    }
}

public enum JunitAttributeError: Swift.Error {
    case failedToAddAttribute(name: String, value: String)
}

extension XMLElement {
    func addAttribute(withName name: String, stringValue: String) throws {
        guard let attribute = XMLNode.attribute(withName: name, stringValue: stringValue) as? XMLNode else {
            throw JunitAttributeError.failedToAddAttribute(name: name, value: stringValue)
        }
        addAttribute(attribute)
    }
}

extension DateFormatter {
    func iso8601(date: Date) -> String {
        dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        timeZone = TimeZone(secondsFromGMT: 0)
        locale = Locale(identifier: "en_US_POSIX")

        return string(from: date)
    }
}
