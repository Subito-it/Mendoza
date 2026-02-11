//
//  SimulatorSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class SimulatorSetupOperation: BaseOperation<[(simulator: Simulator, node: Node)]> {
    private var simulators = [(simulator: Simulator, node: Node)]()

    private let arrangeMaxSimulatorsPerRow = 3
    private let arrangeDisplayMargin = 80
    private let windowMenubarHeight = 38

    private let syncQueue = DispatchQueue(label: String(describing: SimulatorSetupOperation.self))
    private let buildBundleIdentifier: String
    private let testBundleIdentifier: String
    private let nodes: [Node]
    private let device: Device
    private let alwaysRebootSimulators: Bool
    private let verbose: Bool
    private lazy var pool: ConnectionPool = makeConnectionPool(sources: nodes)
    private var cachedScreenResolution: ScreenResolution?

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

                if rebootRequired.contains(true) || self.alwaysRebootSimulators {
                    Thread.sleep(forTimeInterval: 5 * Double(nodeSimulators.count))
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
                queueProxy.disableSafariMenuOnboarding(on: simulator)
                _ = try? queueProxy.disablePasswordAutofill(on: simulator)

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

    private func simulatorsProperlyArranged(executer: Executer, simulators: [Simulator]) throws -> Bool {
        let simulatorProxy = CommandLineProxy.Simulators(executer: executer, verbose: verbose)

        let settings = try simulatorProxy.loadSimulatorSettings()

        guard settings.ScreenConfigurations?.keys.count == 1 else { return false }

        let screenIdentifier = settings.ScreenConfigurations!.keys.first! // swiftlint:disable:this force_unwrapping

        guard let geometries = settings.DevicePreferences?.values.map(\.SimulatorWindowGeometry) else { return false }

        var screenGeometries = [CommandLineProxy.Simulators.Settings.DevicePreferences.WindowGeometry]()
        for geometry in geometries {
            screenGeometries += geometry?.filter { $0.key == screenIdentifier }.map(\.value) ?? []
        }

        let expectSimulatorLocations = (0 ..< simulators.count).compactMap {
            try? arrangedSimulatorCenter(index: $0,
                                         executer: executer,
                                         device: simulators.first!.device, // swiftlint:disable:this force_unwrapping
                                         displayMargin: arrangeDisplayMargin,
                                         totalSimulators: simulators.count,
                                         maxSimulatorsPerRow: arrangeMaxSimulatorsPerRow)
        }

        let expectedScaleFactor = try arrangedScaleFactor(executer: executer,
                                                          device: simulators.first!.device, // swiftlint:disable:this force_unwrapping
                                                          displayMargin: arrangeDisplayMargin,
                                                          totalSimulators: simulators.count,
                                                          maxSimulatorsPerRow: arrangeMaxSimulatorsPerRow)

        for expectSimulatorLocation in expectSimulatorLocations {
            let matchingGeometry = screenGeometries.first {
                // {XXX(.X), YYY(.Y)} -> [CGFloat, CGFloat] conversion
                guard let center = $0.WindowCenter?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                    .components(separatedBy: ",")
                    .compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) })
                    .map({ CGFloat($0) }),
                    center.count == 2
                else {
                    return false
                }

                let match1 = abs(center[0] - expectSimulatorLocation.x) <= 2 && abs(center[1] - expectSimulatorLocation.y) <= 2
                let match2 = abs(center[0] - expectSimulatorLocation.x) <= 2 && abs(center[1] - CGFloat(windowMenubarHeight / 2) - expectSimulatorLocation.y) <= 2

                return match1 || match2
            }
            guard let scale = matchingGeometry?.WindowScale else {
                return false
            }
            guard abs(CGFloat(scale) - expectedScaleFactor) < 0.15 else {
                return false
            }
        }

        let resolution = try screenResolution(executer: executer)
        let simulatorsWindowLocations = try simulatorsWindowLocation(executer: executer)

        for simulatorsWindowLocation in simulatorsWindowLocations {
            let center1 = CGPoint(x: simulatorsWindowLocation.X + simulatorsWindowLocation.Width / 2,
                                  y: resolution.height - (simulatorsWindowLocation.Y + (simulatorsWindowLocation.Height + windowMenubarHeight) / 2))
            let center2 = CGPoint(x: simulatorsWindowLocation.X + simulatorsWindowLocation.Width / 2,
                                  y: resolution.height - (simulatorsWindowLocation.Y + simulatorsWindowLocation.Height / 2))

            let match1 = expectSimulatorLocations.contains(where: { abs($0.x - center1.x) <= 2 && abs($0.y - center1.y) <= 2 })
            let match2 = expectSimulatorLocations.contains(where: { abs($0.x - center2.x) <= 2 && abs($0.y - center2.y) <= 2 })

            guard match1 || match2 else {
                return false
            }
        }

        return true
    }

    /// This method arranges the simulators so that the do not overlap. For simplicity they're arranged on a single row
    ///
    /// Resolutions in points
    /// - iPhone
    ///      iPhone Xs Max: 414 x 896
    ///      iPhone Xʀ: 414 x 896
    ///      iPhone X/Xs: 375 x 812
    ///      iPhone+: 414 x 736
    ///      iPhone [6-8]: 375 x 667
    ///      iPhone 5: 320 x 568
    /// - iPad
    ///      iPad: 768 x 1024
    ///      iPad 10.5': 1112 x 834
    ///      iPad 12.9': 1024 x 1366
    ///
    /// - Note: On Mac (0,0) is the lower left corner
    ///
    /// - Parameters:
    ///   - param1: simulators to arrange
    private func updateSimulatorsSettings(executer: Executer, simulators: [Simulator], arrangeSimulators: Bool) throws -> Bool {
        let simulatorProxy = CommandLineProxy.Simulators(executer: executer, verbose: verbose)

        // Configuration file might not be ready yet
        var loadedSettings: CommandLineProxy.Simulators.Settings?
        var loadedScreenIdentifier: String?
        loadedSettings = try simulatorProxy.loadSimulatorSettings()
        if loadedSettings?.ScreenConfigurations == nil {
            try simulatorProxy.gracefullyQuit()
            try simulatorProxy.launch()

            for _ in 0 ..< 5 {
                Thread.sleep(forTimeInterval: 5.0)
                loadedSettings = try simulatorProxy.loadSimulatorSettings()
                if loadedSettings != nil {
                    break
                }
            }
        }
        if let keys = loadedSettings?.ScreenConfigurations?.keys {
            loadedScreenIdentifier = Array(keys).last ?? ""
        }

        guard let settings = loadedSettings, let screenIdentifier = loadedScreenIdentifier else {
            fatalError("💣 Failed to get screenIdentifier from simulator plist on \(executer.address)")
        }

        var storeConfiguration = false

        settings.CurrentDeviceUDID = nil

        let connectHardwareKeyboardFlag = false

        settings.AllowFullscreenMode = false
        settings.PasteboardAutomaticSync = false
        settings.ShowChrome = false
        settings.ConnectHardwareKeyboard = connectHardwareKeyboardFlag
        settings.OptimizeRenderingForWindowScale = false

        if settings.DevicePreferences == nil {
            settings.DevicePreferences = .init()
        }

        let scaleFactor = try arrangedScaleFactor(executer: executer,
                                                  device: simulators.first!.device, // swiftlint:disable:this force_unwrapping
                                                  displayMargin: arrangeDisplayMargin,
                                                  totalSimulators: simulators.count,
                                                  maxSimulatorsPerRow: arrangeMaxSimulatorsPerRow)

        for (index, simulator) in simulators.enumerated() {
            let center = try arrangedSimulatorCenter(index: index,
                                                     executer: executer,
                                                     device: simulators.first!.device, // swiftlint:disable:this force_unwrapping
                                                     displayMargin: arrangeDisplayMargin,
                                                     totalSimulators: simulators.count,
                                                     maxSimulatorsPerRow: arrangeMaxSimulatorsPerRow)
            let windowCenter = "{\(center.x), \(center.y)}"

            let devicePreferences = settings.DevicePreferences?[simulator.id] ?? .init()
            devicePreferences.SimulatorWindowOrientation = "Portrait"
            devicePreferences.SimulatorWindowRotationAngle = 0
            devicePreferences.ConnectHardwareKeyboard = connectHardwareKeyboardFlag
            if settings.DevicePreferences?[simulator.id] != devicePreferences {
                storeConfiguration = true
            }
            devicePreferences.SimulatorExternalDisplay = nil
            settings.DevicePreferences?[simulator.id] = devicePreferences

            if settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry == nil {
                settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry = .init()
            }

            if arrangeSimulators {
                let windowGeometry = settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry?[screenIdentifier] ?? .init()
                windowGeometry.WindowScale = Double(scaleFactor)
                windowGeometry.WindowCenter = windowCenter
                if settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry?[screenIdentifier] != windowGeometry {
                    storeConfiguration = true
                }
                settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry?[screenIdentifier] = windowGeometry

                executer.logger?.log(command: "Arranging simulator \(simulator.id) on \(executer.address) at location (\(center))")
                executer.logger?.log(output: "", statusCode: 0)

                #if DEBUG
                    print("⚠️ Arranging simulator \(simulator.id) on \(executer.address) at location (\(center))".bold)
                #endif
            }
        }

        try simulatorProxy.storeSimulatorSettings(settings)

        return storeConfiguration
    }

    private func arrangedSimulatorCenter(index: Int, executer: Executer, device: Device, displayMargin: Int, totalSimulators: Int, maxSimulatorsPerRow: Int) throws -> CGPoint {
        let row = index / maxSimulatorsPerRow

        let resolution = try screenResolution(executer: executer)

        let largestDimension = device.pointSize().height
        let availableDimension = (resolution.width - displayMargin * 2) / min(totalSimulators, maxSimulatorsPerRow)

        let scaleFactor = try arrangedScaleFactor(executer: executer,
                                                  device: device,
                                                  displayMargin: displayMargin,
                                                  totalSimulators: totalSimulators,
                                                  maxSimulatorsPerRow: maxSimulatorsPerRow)

        let x = displayMargin + availableDimension / 2 + index * availableDimension - row * (availableDimension * maxSimulatorsPerRow)
        let y = displayMargin + Int(largestDimension * scaleFactor / 2) + Int(largestDimension * scaleFactor + CGFloat(windowMenubarHeight)) * row

        return CGPoint(x: x, y: y)
    }

    private func arrangedScaleFactor(executer: Executer, device: Device, displayMargin: Int, totalSimulators: Int, maxSimulatorsPerRow: Int) throws -> CGFloat {
        let resolution = try screenResolution(executer: executer)

        let rows = totalSimulators / maxSimulatorsPerRow

        let largestDimension = device.pointSize().height
        let availableDimension = (resolution.width - displayMargin * 2) / min(totalSimulators, maxSimulatorsPerRow)
        let availableHeight = min(availableDimension, (resolution.height - 2 * displayMargin) / (rows + 1))
        return CGFloat(availableHeight) / CGFloat(largestDimension)
    }

    private func screenResolution(executer: Executer) throws -> ScreenResolution {
        if let cachedScreenResolution {
            return cachedScreenResolution
        }
        let rawResolution = try executer.execute(#"mendoza mendoza screen_point_size"#)
        cachedScreenResolution = try JSONDecoder().decode(ScreenResolution.self, from: Data(rawResolution.utf8))
        return cachedScreenResolution!
    }

    private func simulatorsWindowLocation(executer: Executer) throws -> [SimulatorWindowLocation] {
        let rawResolution = try executer.execute(#"mendoza mendoza simulator_locations"#)
        return try JSONDecoder().decode([SimulatorWindowLocation].self, from: Data(rawResolution.utf8))
    }
}
