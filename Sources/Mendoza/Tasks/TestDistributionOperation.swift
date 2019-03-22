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
    
    init(device: Device, plugin: TestDistributionPlugin) {
        self.device = device
        self.plugin = plugin
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
            
            var distributedTestCases: [[TestCase]]
            if plugin.isInstalled {
                distributedTestCases = try plugin.run(input: input)
                distributedTestCases += Array(repeating: [], count: testRunnersCount - distributedTestCases.count)
            } else {
                distributedTestCases = input.tests.split(in: testRunnersCount)
            }
            
            assert(distributedTestCases.count == input.testRunnersCount)
            
            for (index, nodeTests) in distributedTestCases.enumerated() {
                logger.log(command: "Node \(index + 1) will launch \(nodeTests.count) test cases")
                logger.log(output: nodeTests.map({ $0.testIdentifier }).joined(separator: "\n"), statusCode: 0)
            }
            
            didEnd?(distributedTestCases)
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
