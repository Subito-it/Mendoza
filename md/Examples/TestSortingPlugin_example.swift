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
struct TestSortingPlugin {
    struct TestCaseExecutionTime: Codable {
        let last_duration_secs: TimeInterval
        let avg_duration_sec: TimeInterval
    }

    func handle(_ input: TestOrderInput, pluginData _: String?) -> [TestCase] {
        var estimatedTests = [(testCase: TestCase, estimatedDuration: Double)]()

        for test in input.tests {
            let testIdentifier = "\(test.suite)-\(test.name)()-\(input.device.name)-\(input.device.runtime)".md5Value
            let url = URL(string: "http://cachi.local:8090/v1/teststats?\(testIdentifier)")! // https://github.com/Subito-it/Cachi

            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: url) { data, _, error in
                defer { sem.signal() }
                guard error == nil, let data = data else { fatalError("Failed fetching execution time\n\n") }
                guard let item = try? JSONDecoder().decode(TestCaseExecutionTime.self, from: data) else {
                    fatalError("Error decoding execution time result\n\n")
                }

                estimatedTests.append((testCase: test, estimatedDuration: item.average_s))
            }.resume()
            guard sem.wait(timeout: .now() + 60.0) == .success else {
                fatalError("Failed fetching execution time results\n\n")
            }
        }

        return estimatedTests.sorted(by: { $0.estimatedDuration > $1.estimatedDuration }).map { $0.testCase }
    }
}
