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
    private lazy var executer: Executer? = {
        let destinationNode = configuration.resultDestination.node
        
        let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
        return try? destinationNode.makeExecuter(logger: logger)
    }()
    
    init(configuration: Configuration, timestamp: String) {
        self.configuration = configuration
        self.timestamp = timestamp
    }

    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            guard let executer = executer else { fatalError("💣 Failed making executer") }
            
            try writeHtmlTestResultSummary(executer: executer)
            try writeJsonTestResultSummary(executer: executer)
            
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
    
    private func writeHtmlTestResultSummary(executer: Executer) throws {
        guard let testCaseResults = testCaseResults else { return }

        let destinationPath = "\(self.configuration.resultDestination.path)/\(self.timestamp)/\(Environment.htmlTestSummaryFilename)"

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
        guard let testCaseResults = testCaseResults else { return }
        
        let destinationPath = "\(self.configuration.resultDestination.path)/\(self.timestamp)/\(Environment.jsonTestSummaryFilename)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let contentData = try? encoder.encode(testCaseResults.sorted(by: { $0.description < $1.description })) else {
            throw Error("Failed writing json test summary data")
        }
        
        let tempUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).json")
        
        try contentData.write(to: tempUrl)
        try executer.upload(localUrl: tempUrl, remotePath: destinationPath)
    }
}

extension TestCaseResult {
    static func html(content: String) -> String {
        let contentMarker = "{{ content }}"
        return
"""
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
