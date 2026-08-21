//
//  TestSortingOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

// If available the plugin should return a list of TestCases sorted from the longest to the shortest estimated execution time

class TestSortingOperation: BaseOperation<[TestCase]> {
    var testCases: [TestCase]?

    private let device: Device
    private let plugin: TestSortingPlugin
    private let verbose: Bool

    init(device: Device, plugin: TestSortingPlugin, verbose: Bool) {
        self.device = device
        self.plugin = plugin
        self.verbose = verbose
        super.init()
        loggers.insert(plugin.logger)
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            guard let testCases = testCases else { fatalError("💣 Required fields not set") }

            didStart?()

            if plugin.isInstalled {
                let input = TestOrderInput(tests: testCases, device: device)
                let sortedTestCases = try plugin.run(input: input)
                try assertIsReordering(sortedTestCases, of: testCases)
                didEnd?(sortedTestCases)
            } else {
                didEnd?(testCases)
            }
        } catch {
            didThrow?(error)
        }
    }

    /// A sorting plugin reorders the suite, it does not select from it. Whatever it returns becomes
    /// the set of tests that run, so a plugin that drops entries would quietly shrink the session and
    /// still report success.
    private func assertIsReordering(_ sortedTestCases: [TestCase], of testCases: [TestCase]) throws {
        if sortedTestCases.count == testCases.count, Set(sortedTestCases) == Set(testCases) { return }

        let missing = Set(testCases).subtracting(sortedTestCases).map(\.testIdentifier).sorted()
        let unexpected = Set(sortedTestCases).subtracting(testCases).map(\.testIdentifier).sorted()

        var reason = "TestSortingPlugin returned \(sortedTestCases.count) test cases, expected the \(testCases.count) it was given."
        if !missing.isEmpty {
            reason += " Missing: \(missing.joined(separator: ", "))."
        }
        if !unexpected.isEmpty {
            reason += " Not part of the input: \(unexpected.joined(separator: ", "))."
        }

        throw Error(reason, logger: plugin.logger)
    }

    override func cancel() {
        if isExecuting {
            plugin.terminate()
        }
        super.cancel()
    }
}
