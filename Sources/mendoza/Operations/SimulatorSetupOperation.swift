//
//  SimulatorSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class SimulatorSetupOperation: BaseOperation<[(simulator: Simulator, node: Node)]> {
    private var simulators = [(simulator: Simulator, node: Node)]()

    let arrangeMaxSimulatorsPerRow = 3
    let arrangeDisplayMargin = 80
    let windowMenubarHeight = 38

    private let syncQueue = DispatchQueue(label: String(describing: SimulatorSetupOperation.self))
    private let buildBundleIdentifier: String
    private let testBundleIdentifier: String
    private let nodes: [Node]
    let device: Device
    private let alwaysRebootSimulators: Bool
    let verbose: Bool
    private lazy var pool: ConnectionPool = makeConnectionPool(sources: nodes)
    var cachedScreenResolution: ScreenResolution?

    init(buildBundleIdentifier: String, testBundleIdentifier: String, nodes: [Node], device: Device, alwaysRebootSimulators: Bool, verbose: Bool) {
        self.buildBundleIdentifier = buildBundleIdentifier
        self.testBundleIdentifier = testBundleIdentifier
        self.nodes = nodes
        self.device = device
        self.alwaysRebootSimulators = alwaysRebootSimulators
        self.verbose = verbose
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            try pool.execute { executer, source in
                try self.deleteAllSimulatorsIfDiskSpaceLow(executer: executer, node: source.node)
                let proxy = CommandLineProxy.Simulators(executer: executer, verbose: self.verbose)

                try proxy.checkIfRuntimeInstalled(self.device.runtime, nodeAddress: source.node.address)

                var rebootRequired = [Bool]()

                try rebootRequired.append(self.shutdownSimulatorOnXcodeVersionMismatch(executer: executer, node: source.node))

                let nodeSimulators = try self.makeSimulators(node: source.node, executer: executer)

                try rebootRequired.append(proxy.deleteSettingsIfNeeded())
                try rebootRequired.append(proxy.enablePasteboardWorkaround())
                try rebootRequired.append(proxy.enableLowQualityGraphicOverrides())
                try rebootRequired.append(proxy.disableSimulatorBezel())
                try rebootRequired.append(self.updateSimulatorsSettings(executer: executer, simulators: nodeSimulators, arrangeSimulators: true))

                for nodeSimulator in nodeSimulators {
                    try rebootRequired.append(proxy.updateLanguage(on: nodeSimulator, language: self.device.language, locale: self.device.locale))
                    try rebootRequired.append(proxy.increaseWatchdogExceptionTimeout(on: nodeSimulator, appBundleIndentifier: self.buildBundleIdentifier, testBundleIdentifier: self.testBundleIdentifier))
                    try rebootRequired.append(proxy.disablePasswordAutofill(on: nodeSimulator))
                }

                if rebootRequired.contains(true) || self.alwaysRebootSimulators {
                    print("Rebooting simulators")

                    try? proxy.shutdownAll() // Always shutting down simulators is the safest way to workaround unexpected Simulator.app hangs
                    try proxy.gracefullyQuit()
                }

                let bootedSimulators = try proxy.bootedSimulators()

                try self.bootSimulators(node: source.node, simulators: nodeSimulators.filter { !bootedSimulators.contains($0) })
                if nodeSimulators.count != bootedSimulators.count {
                    try proxy.launch()
                }

                self.syncQueue.sync { [unowned self] in
                    self.simulators += nodeSimulators.map { (simulator: $0, node: source.node) }
                }
            }

            didEnd?(simulators)
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

    private func makeSimulators(node: Node, executer: Executer) throws -> [Simulator] {
        var concurrentTestRunners: Int
        switch node.concurrentTestRunners {
        case let .manual(count) where count > 0: // swiftlint:disable:this empty_count
            concurrentTestRunners = Int(count)
        default:
            concurrentTestRunners = try physicalCPUs(executer: executer, node: node) / 2
        }
        concurrentTestRunners = max(1, concurrentTestRunners)

        let simulatorNames = (1 ... concurrentTestRunners).map { "\(self.device.name)-\($0)" }

        let proxy = CommandLineProxy.Simulators(executer: executer, verbose: verbose)
        let rawSimulatorStatus = try proxy.rawSimulatorStatus()
        let simulators = try simulatorNames.compactMap { try proxy.makeSimulatorIfNeeded(name: $0, device: self.device, cachedSimulatorStatus: rawSimulatorStatus) }

        return simulators
    }

    private func bootSimulators(node: Node, simulators: [Simulator]) throws {
        let bootQueue = OperationQueue()

        for simulator in simulators {
            let logger = ExecuterLogger(name: "\(type(of: self))-AsyncBoot", address: node.address)
            addLogger(logger)

            let queueExecuter = try node.makeExecuter(logger: logger, environment: nodesEnvironment[node.address] ?? [:])
            let queueProxy = CommandLineProxy.Simulators(executer: queueExecuter, verbose: verbose)

            bootQueue.addOperation {
                #if DEBUG
                    Swift.print("Booting \(simulator.id)")
                #endif
                try? queueProxy.bootSynchronously(simulator: simulator)

                queueProxy.enableXcode11ReleaseNotesWorkarounds(on: simulator)
                _ = try? queueProxy.enableXcode13Workarounds(on: simulator)
                queueProxy.disableSlideToType(on: simulator)
                queueProxy.disableMultilingualKeyboardTip(on: simulator)
                queueProxy.disableSafariMenuOnboarding(on: simulator)

                #if DEBUG
                    Swift.print("Booted \(simulator.id)")
                #endif

                try? logger.dump()
            }
        }
        bootQueue.waitUntilAllOperationsAreFinished()
    }

    private func physicalCPUs(executer: Executer, node _: Node) throws -> Int {
        guard let concurrentTestRunners = try Int(executer.execute("sysctl -n hw.physicalcpu")) else {
            throw Error("Failed getting concurrent simulators", logger: executer.logger)
        }

        return concurrentTestRunners
    }

    private func deleteAllSimulatorsIfDiskSpaceLow(executer: Executer, node: Node) throws {
        var totalSimulators: Int
        switch node.concurrentTestRunners {
        case let .manual(count) where count > 0: // swiftlint:disable:this empty_count
            totalSimulators = Int(count)
        default:
            totalSimulators = try physicalCPUs(executer: executer, node: node) / 2
        }
        totalSimulators = max(1, totalSimulators)

        let requiredSpaceGiB = 4 * totalSimulators // 4 GiB per simulator

        let availableString = try executer.execute("df -g / | awk 'NR==2 {print $4}'")
        guard let availableSpaceGiB = Double(availableString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }

        if availableSpaceGiB < Double(requiredSpaceGiB) {
            print("Low disk space (\(Int(availableSpaceGiB))GiB available, \(requiredSpaceGiB)GiB required). Deleting all simulators on \(node.address).")
            _ = try? executer.execute("xcrun simctl delete all")
        }
    }

    private func shutdownSimulatorOnXcodeVersionMismatch(executer: Executer, node: Node) throws -> Bool {
        let systemPath = try executer.execute("xcode-select -p")
        let path = (nodesEnvironment[node.address]?["DEVELOPER_DIR"]) ?? systemPath
        if try !(executer.execute("ps aux | grep Simulator.app").contains(path)) {
            // Launched Simulator is from a different Xcode version

            _ = try? executer.execute("killall -9 com.apple.CoreSimulator.CoreSimulatorService;") // Killing CoreSimulatorService will reset and shutdown all Simulators
            _ = try? executer.execute("killall Simulator")

            return true
        }

        return false
    }
}
