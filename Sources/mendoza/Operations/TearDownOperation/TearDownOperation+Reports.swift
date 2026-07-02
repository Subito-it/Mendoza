//
//  TearDownOperation+Reports.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

extension TearDownOperation {
    func writeHtmlRepeatedTestResultSummary(executer: Executer) throws {
        guard var repeatedTestCases = testSessionResult?.retriedTests else { return }
        repeatedTestCases = repeatedTestCases.sorted(by: { $0.description < $1.description })

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.htmlRepeatedTestSummaryFilename)"

        var content = "<h2>Result - repeated tests</h2>\n"

        if repeatedTestCases.count > 0 {
            for testCase in repeatedTestCases {
                content += "<p class='failed'>\(testCase)</p>\n"
            }
        } else {
            content += "<p>No repeated tests</p>\n"
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).html")

        guard let contentData = TestCaseResult.html(content: content).data(using: .utf8) else {
            throw Error("Failed writing html repeated test summary data")
        }

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeJsonRepeatedTestResultSummary(executer: Executer) throws {
        guard var repeatedTestCases = testSessionResult?.retriedTests else { return }
        repeatedTestCases = repeatedTestCases.sorted(by: { $0.description < $1.description })

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.jsonRepeatedTestSummaryFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let contentData = try? encoder.encode(repeatedTestCases) else {
            throw Error("Failed writing json repeated test summary data")
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeHtmlTestResultSummary(executer: Executer) throws {
        guard let testSessionResult = testSessionResult else { return }

        var testCaseResults = testSessionResult.passedTests + testSessionResult.failedTests
        testCaseResults = testCaseResults.sorted(by: { $0.description < $1.description })

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.htmlTestSummaryFilename)"

        var content = "<h2>Result</h2>\n"

        for testCase in testCaseResults {
            switch testCase.status {
            case .passed:
                content += "<p class='passed'>✓ \(testCase)</p>\n"
            case .failed:
                content += "<p class='failed'>𝘅 \(testCase)</p>\n"
            }
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).html")

        guard let contentData = TestCaseResult.html(content: content).data(using: .utf8) else {
            throw Error("Failed writing html test summary data")
        }

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeJsonTestResultSummary(executer: Executer) throws {
        guard let testSessionResult = testSessionResult else { return }

        var testCaseResults = testSessionResult.passedTests + testSessionResult.failedTests
        testCaseResults = testCaseResults.sorted(by: { $0.description < $1.description })

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.jsonTestSummaryFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let contentData = try? encoder.encode(testCaseResults.sorted(by: { $0.description < $1.description })) else {
            throw Error("Failed writing json test summary data")
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeJsonTestSuiteResult(executer: Executer) throws {
        guard let testSessionResult = testSessionResult else { return }

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.jsonSuiteResultFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(testSessionResult)

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: tempUrl)

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeHtmlExecutionGraph(executer: Executer) throws {
        guard let testSessionResult = testSessionResult else { return }

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.htmlExecutionGraphFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(testSessionResult)

        let suiteDetailJson = String(decoding: data, as: UTF8.self)

        let executionGraph = ExecutionGraph.template.replacingOccurrences(of: "$$TEST_DETAIL_JSON", with: suiteDetailJson)

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).html")

        try Data(executionGraph.utf8).write(to: tempUrl)

        _ = try executer.execute("mkdir -p '\(destinationPath)'")
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeGitInfo(executer: Executer) throws {
        guard let git = git else { return }

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.jsonGitSummaryFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let contentData = try? encoder.encode(git) else {
            throw Error("Failed writing json git data")
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeConfigurationSummary(executer: Executer) throws {
        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.configurationSummaryFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let contentData = try? encoder.encode(configuration) else {
            throw Error("Failed writing json git data")
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    func writeResultBundleInfoPlist(executer: Executer, infoPlistPath: String) throws {
        guard let git = git else { return }

        let uniqueUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).plist")
        try executer.download(remotePath: infoPlistPath, localUrl: uniqueUrl)

        guard let data = try? Data(contentsOf: uniqueUrl) else { return }

        var infoPlist = try PropertyListDecoder().decode([String: AnyCodable].self, from: data)

        infoPlist["branchName"] = AnyCodable(git.branch)
        infoPlist["commitMessage"] = AnyCodable(git.commitMessage)
        infoPlist["commitHash"] = AnyCodable(git.commitHash)
        infoPlist["metadata"] = AnyCodable(plugin.plugin.data)
        infoPlist["sourceBasePath"] = AnyCodable(git.url.path)

        if let startTime = testSessionResult?.startTime {
            infoPlist["startDate"] = AnyCodable(Date(timeIntervalSinceReferenceDate: startTime))
            infoPlist["endDate"] = AnyCodable(Date())
        }

        guard let contentData = try? PropertyListEncoder().encode(infoPlist) else {
            throw Error("Failed writing json git data to xcresult bundle Info.plit")
        }

        try contentData.write(to: uniqueUrl)
        try executer.upload(localUrl: uniqueUrl, remotePath: infoPlistPath)
    }
}
