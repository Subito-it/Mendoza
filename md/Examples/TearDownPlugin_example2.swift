#!/usr/bin/swift

import Foundation

// struct GitStatus: Codable {
//     var url: URL
//     var branch: String
//     var commitMessage: String
//     var commitHash: String
// }

// struct TestCaseResult: Codable {
//     var node: String
//     var xcResultPath: String
//     var suite: String
//     var name: String
//     var status: Status
//     var duration: Double
//     var testCaseIDs: Array<String>
//     var testTags: Array<String>
// }

// class TestSessionResult: Codable {
//     var operationExecutionTime: Dictionary<String, Double>
//     var nodes: Dictionary<String, NodeStatistics>
//     var git: Optional<GitStatus>
//     var passedTests: Array<TestCaseResult>
//     var failedTests: Array<TestCaseResult>
//     var destination: Destination
//     var device: Device
//     var xcResultPath: Dictionary<String, String>
//     var date: String
//     var startTime: Double
// }

// class Destination: Codable {
//     var username: String
//     var address: String
//     var path: String
// }

// enum Status: Int, Codable {
//     case passed, failed
// }

// struct Device: Codable {
//     var name: String
//     var osVersion: String
//     var runtime: String
// }

// class NodeStatistics: Codable {
//     var executionTime: Double
//     var totalTests: Int
// }

struct TearDownPlugin {
    func handle(_ input: TestSessionResult, pluginData: String?) {
        let testSessionResult = input

        print("Branch:  \(testSessionResult.git?.branch ?? "Unknown")")
        print("Device:  \(testSessionResult.device.name)")
        print("Runtime: \(testSessionResult.device.osVersion)")

        let testResults = testSessionResult.passedTests + testSessionResult.failedTests

        let groupedItems = Dictionary(grouping: testResults, by: { $0.suite })

        var resultsTable = [[String]]()

        let testStatus = groupedItems.map { (arg: (key: String, value: [TestCaseResult])) -> [String] in
            let (key, value) = arg
            let passTestCases   = value.filter { $0.status == .passed }.unique()
            let failedTestCases = value.filter { $0.status == .failed }.unique()
            let totalTestCases  = passTestCases + failedTestCases

            return [key, String(passTestCases.count), String(failedTestCases.count), String(totalTestCases.count)]
        }

        let totalPassed = String(testSessionResult.passedTests.unique().count)
        let totalFailed = String(testSessionResult.failedTests.unique().count)
        let total = String(testResults.unique().count)
        
        resultsTable.append(["Tags", "Passed", "Failed", "Total"])
        resultsTable.append(contentsOf: testStatus)
        resultsTable.append(["", totalPassed, totalFailed, total])

        var table = Table()

        print("\n")
        table.put(resultsTable)  
        print("\n")

        if testSessionResult.failedTests.count > 0 {
            var failedTestsTable = [[String]]()

            let testCases = testSessionResult.failedTests.map { [$0.name, $0.testCaseIDs.joined(separator: " ")] }

            failedTestsTable.append(["Failed Tests", "TestCase IDs"])
            failedTestsTable.append(contentsOf: testCases)
        
            table.put(failedTestsTable)
            print("\n")
        }
    }
}

extension Sequence where Iterator.Element == TestCaseResult {
    func unique() -> [Iterator.Element] {
        var result:[TestCaseResult] = []

        self.forEach { (testcase) -> () in
            if !result.contains(where: { $0.suite == testcase.suite && $0.name == testcase.name }) {
                result.append(testcase)
            }
        }

        return result
    }  
}

protocol PrinterType {
    func put(_ string: String)
}

struct Printer: PrinterType {
    func put(_ string: String) {
        print(string)
    }
}

public struct Table {

    lazy var printer: PrinterType = {
        Printer()
    }()

    public init() {}

    public mutating func put<T>(_ data: [[T]]) {
        guard let firstRow = data.first, !firstRow.isEmpty else {
            printer.put("")
            return
        }

        let borderString = borderStringForData(data)
        printer.put(borderString)

        data.forEach { row in
            let rowString = zip(row, columns(data)).map { String(describing: $0).padding($1.maxWidth()) }.reduce("|") { $0 + $1 + "|" }

            printer.put(rowString)
            printer.put(borderString)
        }
    }

    func borderStringForData<T>(_ data: [[T]]) -> String {
        return columns(data).map { "-".repeated($0.maxWidth() + 2) }.reduce("+") { $0 + $1 + "+" }
    }

    func columns<T>(_ data: [[T]]) -> [[T]] {
        var result = [[T]]()
        for i in (0..<(data.first?.count ?? 0)) {
            result.append(data.map { $0[i] })
        }
        return result
    }

}

extension Array {
    func maxWidth() -> Int {
        guard let maxElement = self.max(by: { a, b in
            return String(describing: a).count < String(describing: b).count
        }) else { return 0 }
        return String(describing: maxElement).count
    }
}

extension String {
    func padding(_ padding: Int) -> String {
        let padding = padding + 1 - self.count
        guard padding >= 0 else { return self }
        return " " + self + " ".repeated(padding)
    }

    func repeated(_ count: Int) -> String {
        return Array(repeating: self, count: count).joined(separator: "")
    }
}
