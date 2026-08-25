//
//  TearDownOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TearDownOperation: BaseOperation<Void> {
    var testSessionResult: TestSessionResult?

    private lazy var pool: ConnectionPool = makeConnectionPool(sources: configuration.nodes)

    let timestamp: String
    let git: GitStatus?
    private lazy var executer: Executer? = {
        let destinationNode = configuration.resultDestination.node

        let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
        return try? destinationNode.makeExecuter(logger: logger, environment: nodesEnvironment[destinationNode.address] ?? [:])
    }()

    let plugin: TearDownPlugin
    let configuration: Configuration

    init(configuration: Configuration, git: GitStatus?, timestamp: String, plugin: TearDownPlugin) {
        self.configuration = configuration
        self.git = git
        self.timestamp = timestamp
        self.plugin = plugin
        super.init()
        loggers.insert(plugin.logger)
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            guard let executer = executer else { fatalError("💣 Failed making executer") }

            let hasTestResults = testSessionResult?.totalTestCount ?? 0 > 0
            if hasTestResults {
                logTestsResult()

                try writeHtmlRepeatedTestResultSummary(executer: executer)
                try writeJsonRepeatedTestResultSummary(executer: executer)
                try writeHtmlTestResultSummary(executer: executer)
                try writeJsonTestResultSummary(executer: executer)
                try writeJsonTestSuiteResult(executer: executer)
                try writeHtmlExecutionGraph(executer: executer)
                try writeGitInfo(executer: executer)
                try writeConfigurationSummary(executer: executer)

                let infoPlistPath: String
                if !configuration.testing.skipResultMerge {
                    infoPlistPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.resultFoldername)/\(Environment.xcresultFilename)/Info.plist"
                } else {
                    infoPlistPath = "\(configuration.resultDestination.path)/\(timestamp)/\(Environment.resultFoldername)/\(Environment.xcresultFirstUnmergedFilename)/Info.plist"
                }
                try writeResultBundleInfoPlist(executer: executer, infoPlistPath: infoPlistPath)

                if configuration.testing.autodeleteSlowDevices {
                    try? deleteSlowDevices()
                }
            }

            try pool.execute { executer, source in
                if AddressType(node: source.node) == .remote {
                    _ = try? executer.execute("rm -rf '\(Path.base.rawValue)'")
                }
            }

            if plugin.isInstalled {
                guard let testSessionResult = testSessionResult else { fatalError("💣 Required fields not set") }
                _ = try plugin.run(input: testSessionResult)
            }

            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }

    override func cancel() {
        if isExecuting {
            pool.terminate()
        }
        super.cancel()
    }

    private func logTestsResult() {
        if let failedTestCases = testSessionResult?.failedTests, failedTestCases.isEmpty == false {
            print("\nThe following tests failed:".red)
            let failedTestNames = Array(Set(failedTestCases.map { "\($0.suite)/\($0.name)" })).sorted()
            for failedTestName in failedTestNames {
                print("❌ \(failedTestName)")
            }
            print("")
        } else {
            print("\n✅ All tests passed!\n".green)
        }
    }

    private func deleteSlowDevices() throws {
        // Here we check that there are no nodes that started executing its tests with a delay compared to the average of other nodes.
        // This can be clearly seen in the test_graph.html output where it can be seen how all tests require a significant amount of
        // time to start executing. This significantly impacts the total execution time of the test.
        // Once this starts happening in one session it will occur in all subsequent ones and the only way to fix this is to delete
        // the simulator and create a new one.

        let runnerOperationKey = "\(TestRunnerOperation.self)"
        guard let testSessionResult,
              let testOperationStartTime = testSessionResult.operationStartInterval[runnerOperationKey]
        else {
            return
        }

        let testsByNode = Dictionary(grouping: testSessionResult.tests, by: { $0.node }) as [String: [TestCaseResult]]

        var testStartTimeByNode = [String: TimeInterval]()
        for (node, tests) in testsByNode {
            if let nodeTestStartInterval = tests.map(\.startInterval).sorted().first(where: { $0 > 0 }) {
                testStartTimeByNode[node] = nodeTestStartInterval
            }
        }

        // Nodes can end up in a state where they take very long time to start executing the first test.
        // When this happens it has been empirically proven that deleting simulators fixes the problem on
        // subsequent test executions
        let threshold = 40.0
        let performReset = testStartTimeByNode.filter { $0.value - testOperationStartTime > threshold }.map(\.key)

        if !performReset.isEmpty {
            print("\nℹ️ Slow devices found on \(performReset.joined(separator: ", ")). Deleting simulators...".bold.yellow)

            try pool.execute { executer, source in
                if performReset.contains(source.node.address) {
                    let proxy = CommandLineProxy.Simulators(executer: executer, verbose: false)
                    try proxy.deleteAll()
                }
            }
        }
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
