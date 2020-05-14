//
//  TestTearDownOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestTearDownOperation: BaseOperation<Void> {
    var testCaseResults: [TestCaseResult]?

    private let configuration: Configuration
    private let timestamp: String
    private let git: GitStatus?
    private lazy var executer: Executer? = {
        let destinationNode = configuration.resultDestination.node

        let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
        return try? destinationNode.makeExecuter(logger: logger)
    }()

    init(configuration: Configuration, git: GitStatus?, timestamp: String) {
        self.configuration = configuration
        self.git = git
        self.timestamp = timestamp
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            guard let executer = executer else {
                fatalError("💣 Failed making executer")
            }

            try writeHtmlRepeatedTestResultSummary(executer: executer)
            try writeJsonRepeatedTestResultSummary(executer: executer)
            try writeHtmlTestResultSummary(executer: executer)
            try writeJsonTestResultSummary(executer: executer)
            try writeGitInfo(executer: executer)
            try writeGitInfoInResultBundleInfoPlist(executer: executer)

            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }

    override func cancel() {
        if isExecuting {
            executer?.terminate()
        }
        super.cancel()
    }

    private func filterRetriedTestsFromCaseResults(_ testCaseResults: [TestCaseResult]?) -> [TestCaseResult]? {
        guard let testCaseResults = testCaseResults else { return nil }

        var filteredTestCaseResults = [TestCaseResult]()
        for (_, values) in Dictionary(grouping: testCaseResults, by: { "\($0.suite)_\($0.name)" }) {
            guard let testCaseResult = values.first(where: { $0.status == .passed }) ?? values.first else { continue }

            filteredTestCaseResults.append(testCaseResult)
        }

        return filteredTestCaseResults
    }

    private func writeHtmlRepeatedTestResultSummary(executer: Executer) throws {
        guard let testCaseResults = testCaseResults else { return }

        let repeatedTestCases = Dictionary(grouping: testCaseResults, by: { "\($0.suite)_\($0.name)" }).filter { $1.count > 1 }.keys

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.htmlRepeatedTestSummaryFilename)"

        var content = "<h2>Result - repeated tests</h2>\n"

        for testCase in Array(repeatedTestCases).sorted() {
            content += "<p class='failed'>\(testCase)</p>\n"
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).html")

        guard let contentData = TestCaseResult.html(content: content).data(using: .utf8) else {
            throw Error("Failed writing html repeated test summary data")
        }

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    private func writeJsonRepeatedTestResultSummary(executer: Executer) throws {
        guard let testCaseResults = testCaseResults else { return }

        let repeatedTestCases = Dictionary(grouping: testCaseResults, by: { "\($0.suite)_\($0.name)" }).filter { $1.count > 1 }.keys

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.jsonRepeatedTestSummaryFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let contentData = try? encoder.encode(Array(repeatedTestCases).sorted()) else {
            throw Error("Failed writing json repeated test summary data")
        }

        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")

        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }

    private func writeHtmlTestResultSummary(executer: Executer) throws {
        guard let testCaseResults = filterRetriedTestsFromCaseResults(testCaseResults) else { return }

        let destinationPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.htmlTestSummaryFilename)"

        var content = "<h2>Result</h2>\n"

        for testCase in testCaseResults.sorted(by: { $0.description < $1.description }) {
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

    private func writeJsonTestResultSummary(executer: Executer) throws {
        guard let testCaseResults = filterRetriedTestsFromCaseResults(testCaseResults) else { return }

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

    private func writeGitInfo(executer: Executer) throws {
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

    private func writeGitInfoInResultBundleInfoPlist(executer: Executer) throws {
        guard let git = git else { return }

        let infoPlistPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.xcresultFilename)/Info.plist"

        let uniqueUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).plist")
        try executer.download(remotePath: infoPlistPath, localUrl: uniqueUrl)

        guard let data = try? Data(contentsOf: uniqueUrl) else { return }

        var infoPlist = try PropertyListDecoder().decode([String: AnyCodable].self, from: data)

        infoPlist["branchName"] = AnyCodable(git.branch)
        infoPlist["commitMessage"] = AnyCodable(git.commitMessage)
        infoPlist["commitHash"] = AnyCodable(git.commitHash)

        guard let contentData = try? PropertyListEncoder().encode(infoPlist) else {
            throw Error("Failed writing json git data to xcresult bundle Info.plit")
        }

        try contentData.write(to: uniqueUrl)
        try executer.upload(localUrl: uniqueUrl, remotePath: infoPlistPath)
    }
}

extension TestCaseResult {
    static func html(content: String) -> String {
        let contentMarker = "{{ content }}"
        return """
        <html>
        <meta charset="UTF-8">
        <head>
            <style>
                body {
                    font-family: Menlo, Courier;
                    font-weight: normal;
                    color: rgb(30, 30, 30);
                    font-size: 80%;
                    margin-left: 20px;
                }
                p {
                    font-weight: lighter;
                }
                p.passed {
                    color: rgb(20,149,61);
                }
                p.failed {
                    color: rgb(223,26,33);
                }
                summary::-webkit-details-marker {
                    display: none;
                }
            </style>
        </head>
        <body>
        \(contentMarker)
        </body>
        </html>
        """.replacingOccurrences(of: contentMarker, with: content)
    }
}
