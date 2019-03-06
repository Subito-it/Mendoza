#!/usr/bin/swift
// swiftlint:disable all

import Foundation

// struct TestOrderInput: Codable {
//     var tests: Array<TestCase>
//     var simulatorCount: Int
//     var device: Device
// }
// 
// struct TestCase: Codable {
//     var name: String
//     var suite: String
// }
// 
// struct Device: Codable {
//     var name: String
//     var version: String
// }
// 
struct TestDistributionPlugin {
    struct TestCaseExecutionTime: Codable {
        let last_duration_secs: TimeInterval
        let avg_duration_sec: TimeInterval
    }

    func handle(_ input: TestOrderInput, pluginData: String?) -> Array<Array<TestCase>> {
        var testExecutionTimes = [(test: TestCase, duration: TimeInterval)]()

        for test in input.tests {
            let url = URL(string: "http://testcollector.local:8090/teststats?id=\(test.suite)/\(test.name)")!
            
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: url) { (data, _, error) in
                defer { sem.signal() }
                guard error == nil, let data = data else { fatalError("Failed fetching execution time\n\n") }
                guard let item = try? JSONDecoder().decode(TestCaseExecutionTime.self, from: data) else {
                    fatalError("Error decoding execution time result\n\n")
                }
                
                testExecutionTimes.append((test, item.avg_duration_sec))
            }.resume()
            guard sem.wait(timeout: .now() + 60.0) == .success else {
                fatalError("Failed fetching execution time results\n\n")
            }
        }

        let testWithDuration = testExecutionTimes.map { $0.duration }.filter { $0 > 0.0 }
        let meanDuration = max(testWithDuration.reduce(0.0, +) / Double(max(1, testWithDuration.count)), 1.0)

        // Add average execution time to tests with unknown duration
        testExecutionTimes = testExecutionTimes.map { $0.duration > 0.0 ? $0 : ($0.test, meanDuration) }

        // Add startup overhead to tests. This should allow better distribution
        let startupOverhead = 5.0
        testExecutionTimes = testExecutionTimes.map { ($0.test, $0.duration + startupOverhead) }

        // Distribute
        // `testExecutionTimes` is sorted with longest tests first
        // with round-robin logic we assign tests to the result array
        // when completing a round we resort result so that shortes results come always first
        // this should guarantee a simple implementation to equally distribute total execution time
        testExecutionTimes.sort { $0.duration > $1.duration }

        var result = Array(repeating: [(test: TestCase, duration: Double)](), count: input.simulatorCount)
        var simulatorIndex = 0
        for test in testExecutionTimes {
            result[simulatorIndex].append((test: test.test, duration: test.duration))
            
            simulatorIndex += 1
            if simulatorIndex == input.simulatorCount {
                simulatorIndex = 0
                // sort ascending so that simulatorIndex = 0 is always the shortest
                result.sort { lhs, rhs in
                    let lhsDuration = lhs.map { $0.duration }.reduce(0, +)
                    let rhsDuration = rhs.map { $0.duration }.reduce(0, +)
                    return lhsDuration < rhsDuration
                }
            }
        }

        let distributionResult = result.map { $0.map { $0.test }}
        return distributionResult.filter { $0.count > 0 }
    }
}
