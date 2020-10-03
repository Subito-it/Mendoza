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
    private let configuration: Configuration
    private let nodes: [Node]
    private let device: Device
    private let runHeadless: Bool
    private let verbose: Bool
    private lazy var pool: ConnectionPool = {
        makeConnectionPool(sources: nodes)
    }()

    init(configuration: Configuration, nodes: [Node], device: Device, runHeadless: Bool, verbose: Bool) {
        self.nodes = nodes
        self.configuration = configuration
        self.device = device
        self.runHeadless = runHeadless
        self.verbose = verbose
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let appleIdCredentials = configuration.appleIdCredentials()

            try pool.execute { executer, source in
                let node = source.node

                let proxy = CommandLineProxy.Simulators(executer: executer, verbose: self.verbose)

                try proxy.installRuntimeIfNeeded(self.device.runtime, nodeAddress: node.address, appleIdCredentials: appleIdCredentials, administratorPassword: node.administratorPassword ?? nil) // swiftlint:disable:this redundant_nil_coalescing

                let concurrentTestRunners: Int
                switch node.concurrentTestRunners {
                case let .manual(count) where count > 0: // swiftlint:disable:this empty_count
                    concurrentTestRunners = Int(count)
                default:
                    concurrentTestRunners = try self.physicalCPUs(executer: executer, node: node)
                }

                let simulatorNames = (1 ... concurrentTestRunners).map { "\(self.device.name)-\($0)" }

                let rawSimulatorStatus = try proxy.rawSimulatorStatus()
                let nodeSimulators = try simulatorNames.compactMap { try proxy.makeSimulatorIfNeeded(name: $0, device: self.device, cachedSimulatorStatus: rawSimulatorStatus) }

                try proxy.rewriteSettingsIfNeeded()

                try proxy.enablePasteboardWorkaround()
                try proxy.enableLowQualityGraphicOverrides()
                try proxy.disableSimulatorBezel()

                var simulatorsProperlyArranged = true
                if self.runHeadless == false {
                    simulatorsProperlyArranged = try self.simulatorsProperlyArranged(executer: executer, simulators: nodeSimulators)
                let shouldArrangeSimulators = self.runHeadless == false
                try self.updateSimulatorsSettings(executer: executer, simulators: nodeSimulators, arrangeSimulators: shouldArrangeSimulators)
                var shouldRebootSimulators = false
                for nodeSimulator in nodeSimulators {
                    let languageUpdated = try proxy.updateLanguage(on: nodeSimulator, language: self.device.language)
                    shouldRebootSimulators = shouldRebootSimulators || languageUpdated
                }

                    if !simulatorsProperlyArranged {
                        try proxy.gracefullyQuit()
                    }
                }

                try nodeSimulators.forEach { try proxy.bootSynchronously(simulator: $0) }

                for nodeSimulator in nodeSimulators {
                    try proxy.enableXcode11ReleaseNotesWorkarounds(on: nodeSimulator)
                    try proxy.disableSlideToType(on: nodeSimulator)
                }

                let bootedSimulators = try proxy.bootedSimulators()
                for simulator in bootedSimulators {
                    try proxy.terminateApp(identifier: self.configuration.buildBundleIdentifier, on: simulator)
                    try proxy.terminateApp(identifier: self.configuration.testBundleIdentifier, on: simulator)
                }

                let unusedSimulators = bootedSimulators.filter { !nodeSimulators.contains($0) }
                for unusedSimulator in unusedSimulators {
                    try proxy.shutdown(simulator: unusedSimulator)
                }

                if self.runHeadless == false {
                    try proxy.launch()
                } else {
                    try proxy.gracefullyQuit()
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

    private func physicalCPUs(executer: Executer, node _: Node) throws -> Int {
        guard let concurrentTestRunners = Int(try executer.execute("sysctl -n hw.physicalcpu")) else {
            throw Error("Failed getting concurrent simulators", logger: executer.logger)
        }

        return concurrentTestRunners
    }

    private func simulatorsProperlyArranged(executer: Executer, simulators: [Simulator]) throws -> Bool {
        let simulatorProxy = CommandLineProxy.Simulators(executer: executer, verbose: verbose)

        let settings = try simulatorProxy.loadSimulatorSettings()

        guard settings.ScreenConfigurations?.keys.count == 1 else { return false }

        let screenIdentifier = settings.ScreenConfigurations!.keys.first! // swiftlint:disable:this force_unwrapping

        guard let geometries = settings.DevicePreferences?.values.map({ $0.SimulatorWindowGeometry }) else { return false }

        var screenGeometries = [CommandLineProxy.Simulators.Settings.DevicePreferences.WindowGeometry]()
        for geometry in geometries {
            screenGeometries += geometry?.filter { $0.key == screenIdentifier }.map { $0.value } ?? []
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
                    center.count == 2 else {
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
    private func updateSimulatorsSettings(executer: Executer, simulators: [Simulator], arrangeSimulators: Bool) throws {
        let simulatorProxy = CommandLineProxy.Simulators(executer: executer, verbose: verbose)

        // Configuration file might not be ready yet
        var loadSettings: CommandLineProxy.Simulators.Settings?
        var loadScreenIdentifier: String?
        for _ in 0 ..< 5 {
            loadSettings = try simulatorProxy.loadSimulatorSettings()
            if let keys = loadSettings?.ScreenConfigurations?.keys {
                loadScreenIdentifier = Array(keys).last ?? ""
                if loadScreenIdentifier?.isEmpty == false {
                    break
                }
            }
            Thread.sleep(forTimeInterval: 3.0)
        }

        guard let settings = loadSettings, let screenIdentifier = loadScreenIdentifier else {
            fatalError("💣 Failed to get screenIdentifier from simulator plist")
        }

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
            devicePreferences.SimulatorExternalDisplay = nil
            devicePreferences.SimulatorWindowOrientation = "Portrait"
            devicePreferences.SimulatorWindowRotationAngle = 0
            devicePreferences.ConnectHardwareKeyboard = connectHardwareKeyboardFlag
            settings.DevicePreferences?[simulator.id] = devicePreferences

            if settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry == nil {
                settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry = .init()
            }

            if arrangeSimulators {
            let windowGeometry = settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry?[screenIdentifier] ?? .init()
            windowGeometry.WindowScale = Double(scaleFactor)
            windowGeometry.WindowCenter = windowCenter
            settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry?[screenIdentifier] = windowGeometry

            executer.logger?.log(command: "Arranging simulator \(simulator.id) on \(executer.address) at location (\(center))")
            executer.logger?.log(output: "", statusCode: 0)

            #if DEBUG
                print("⚠️ Arranging simulator \(simulator.id) on \(executer.address) at location (\(center))".bold)
            #endif
        }
        }

        try simulatorProxy.storeSimulatorSettings(settings)
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
        let rawResolution = try executer.execute(#"mendoza mendoza screen_point_size"#)
        return try JSONDecoder().decode(ScreenResolution.self, from: Data(rawResolution.utf8))
    }

    private func simulatorsWindowLocation(executer: Executer) throws -> [SimulatorWindowLocation] {
        let rawResolution = try executer.execute(#"mendoza mendoza simulator_locations"#)
        return try JSONDecoder().decode([SimulatorWindowLocation].self, from: Data(rawResolution.utf8))
    }
}
