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
                didEnd?(try plugin.run(input: input))
            } else {
                didEnd?(testCases)
            }
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
