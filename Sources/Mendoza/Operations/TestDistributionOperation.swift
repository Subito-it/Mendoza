//
//  TestDistributionOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TestDistributionOperation: BaseOperation<[[TestCase]]> {
    var testRunnersCount: Int?
    var testCases: [TestCase]?
    
    private let device: Device
    private let plugin: TestDistributionPlugin
    private let verbose: Bool
    
    init(device: Device, plugin: TestDistributionPlugin, verbose: Bool) {
        self.device = device
        self.plugin = plugin
        self.verbose = verbose
        super.init()
        loggers.insert(plugin.logger)
    }

    override func main() {
        guard !isCancelled else { return }
        
        do {
            guard let testRunnersCount = testRunnersCount
                , testRunnersCount > 0
                , let testCases = testCases else { fatalError("💣 Required fields not set") }
            
            didStart?()
            
            let input = TestOrderInput(tests: testCases, testRunnersCount: testRunnersCount, device: device)
            
            var distributedTestCases: [[EstimatedTestCase]]
            if plugin.isInstalled {
                distributedTestCases = try plugin.run(input: input)
                distributedTestCases += Array(repeating: [], count: testRunnersCount - distributedTestCases.count)
            } else {
                let estimatedTestCases = input.tests.map { EstimatedTestCase(testCase: $0, estimatedDuration: nil) }
                distributedTestCases = estimatedTestCases.split(in: testRunnersCount)
            }
            
            assert(distributedTestCases.count == input.testRunnersCount)
            
            for (index, nodeEstimatedTests) in distributedTestCases.enumerated() {
                let testsWithDuration = nodeEstimatedTests.filter { $0.estimatedDuration != nil }
                var totalDuration = testsWithDuration.reduce(0, { $0 + $1.estimatedDuration! })
                let averageDuration: TimeInterval = testsWithDuration.count == 0 ? 0 : TimeInterval(totalDuration) / TimeInterval(testsWithDuration.count)
                totalDuration += TimeInterval(nodeEstimatedTests.count - testsWithDuration.count) * averageDuration
                
                let logMessage1 = "Node {\(index)} will launch \(nodeEstimatedTests.count) test cases. Expected execution time \(totalDuration)s"
                let logMessage2 = nodeEstimatedTests.map({ "\($0.testCase.testIdentifier) expected in \($0.estimatedDuration ?? averageDuration)" }).joined(separator: "\n")
                
                if self.verbose && nodeEstimatedTests.count > 0 {
                    print("ℹ️  \(logMessage1)".magenta)
                    print("ℹ️  \(logMessage2)".magenta)
                }
                                
                logger.log(command: logMessage1)
                logger.log(output: logMessage2, statusCode: 0)
            }
            
            didEnd?(distributedTestCases.map { $0.map { $0.testCase }})
        } catch {
            didThrow?(error)
        }
    }
    
    override func cancel() {
        if isExecuting {
            plugin.terminate()
        }
        super.cancel()
    }
}
