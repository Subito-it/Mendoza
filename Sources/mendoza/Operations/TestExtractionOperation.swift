//
//  TestExtractionOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestExtractionOperation: BaseOperation<[TestCase]> {
    private let configuration: Configuration
    private let baseUrl: URL
    private let testTargetSourceFiles: [String]
    private let filePatterns: FilePatterns
    private let device: Device
    private let plugin: TestExtractionPlugin
    private lazy var executer: Executer = {
        makeLocalExecuter()
    }()

    init(configuration: Configuration, baseUrl: URL, testTargetSourceFiles: [String], filePatterns: FilePatterns, device: Device, plugin: TestExtractionPlugin) {
        self.configuration = configuration
        self.baseUrl = baseUrl
        self.testTargetSourceFiles = testTargetSourceFiles
        self.filePatterns = filePatterns
        self.device = device
        self.plugin = plugin
        super.init()
        loggers.insert(plugin.logger)
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let targetTestFiles = try extractTestingFiles()

            let testCases: [TestCase]
            if plugin.isInstalled {
                let input = TestExtractionInput(candidates: targetTestFiles, device: device)
                testCases = try plugin.run(input: input)
            } else {
                let parser = XCTestFileParser()
                testCases = try parser.extractTestCases(from: targetTestFiles)
            }

            guard !testCases.isEmpty else {
                throw Error("❌  No test cases found.\n\nMendoza did look into the following files but found no subclasses of XCTestCase:\n\(targetTestFiles.map(\.path).joined(separator: "\n"))".red.bold)
            }

            print("\nℹ️  Will execute \(testCases.count) tests\n".magenta)

            didEnd?(testCases)
        } catch {
            didThrow?(error)
        }
    }

    override func cancel() {
        if isExecuting {
            plugin.terminate()
            executer.terminate()
        }
        super.cancel()
    }

    private func extractTestingFiles() throws -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: baseUrl, includingPropertiesForKeys: nil)

        let includeRegex = filePatterns.include.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
        let excludeRegex = filePatterns.exclude.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

        var testFileUrls = [URL]()
        while let url = enumerator?.nextObject() as? URL {
            let path = url.path

            if testTargetSourceFiles.contains(where: { path.hasSuffix($0) }) {
                let matchesInclude = includeRegex.contains(where: { $0.firstMatch(in: path, range: NSRange(location: 0, length: path.count)) != nil })
                let matchesExclude = excludeRegex.contains(where: { $0.firstMatch(in: path, range: NSRange(location: 0, length: path.count)) != nil })

                if matchesInclude, !matchesExclude {
                    testFileUrls.append(url)
                }
            }
        }

        return testFileUrls
    }
}
