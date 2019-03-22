//
//  SimulatorSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class SimulatorSetupOperation: BaseOperation<[(simulator: Simulator, node: Node)]> {
    private var simulators = [(simulator: Simulator, node: Node)]()
    
    private let syncQueue = DispatchQueue(label: String(describing: SimulatorSetupOperation.self))
    private let configuration: Configuration
    private let nodes: [Node]
    private let device: Device
    private lazy var pool: ConnectionPool = {
        return makeConnectionPool(sources: nodes)
    }()
    
    init(configuration: Configuration, nodes: [Node], device: Device) {
        self.nodes = nodes
        self.configuration = configuration
        self.device = device
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            let appleIdCredentials = configuration.appleIdCredentials()
            
            try pool.execute { (executer, source) in
                let node = source.node
                
                let proxy = CommandLineProxy.Simulators(executer: executer)

                try proxy.reset()
                try proxy.installRuntimeIfNeeded(self.device.runtime, nodeAddress: node.address, appleIdCredentials: appleIdCredentials, administratorPassword: node.administratorPassword ?? nil)
                
                let concurrentTestRunners = try self.physicalCPUs(executer: executer, node: node)
                let simulatorNames = (1...concurrentTestRunners).map { "\(self.device.name)-\($0)" }
                
                let nodeSimulators = try simulatorNames.compactMap { try proxy.makeSimulatorIfNeeded(name: $0, device: self.device) }
                
                try self.updateSimulatorsArrangement(executer: executer, simulators: nodeSimulators)
                
                self.syncQueue.sync {
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
    
    private func physicalCPUs(executer: Executer, node: Node) throws -> Int {
        guard let concurrentTestRunners = Int(try executer.execute("sysctl -n hw.physicalcpu")) else {
            throw Error("Failed getting concurrent simulators", logger: executer.logger)
        }

        return concurrentTestRunners
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
    private func updateSimulatorsArrangement(executer: Executer, simulators: [Simulator]) throws {
        let simulatorProxy = CommandLineProxy.Simulators(executer: executer)
        
        let settings = try simulatorProxy.fetchSimulatorSettings()
        guard let screenConfiguration = settings.ScreenConfigurations
            , let screenIdentifier = Array(screenConfiguration.keys).last else {
            fatalError("💣 Failed to get screenIdentifier from simulator plist")
        }
        
        settings.CurrentDeviceUDID = nil
        
        settings.AllowFullscreenMode = false
        settings.PasteboardAutomaticSync = false
        settings.ShowChrome = false
        settings.ConnectHardwareKeyboard = false
        settings.OptimizeRenderingForWindowScale = false
        
        if settings.DevicePreferences == nil {
            settings.DevicePreferences = .init()
        }
        
        let resolution = try screenResolution(executer: executer)

        // for simplicity we take the largest width (considering device in landscape)
        let actualWidth = (simulators.first?.name.contains("iPhone") == true) ? 896 : 1366
        // for further simplicity we calculate scale factor for layout on a single row
        let scaledWidth = resolution.width / simulators.count
        let scaleFactor = Double(scaledWidth) / Double(actualWidth)

        let menubarHeight = 30
        for (index, simulator) in simulators.enumerated() {
            let x = index * scaledWidth + scaledWidth / 2
            let y = scaledWidth + menubarHeight
            let center = "{\(x), \(y)}"
            
            let devicePreferences = settings.DevicePreferences?[simulator.id] ?? .init()
            devicePreferences.SimulatorExternalDisplay = nil
            devicePreferences.SimulatorWindowOrientation = "Portrait"
            devicePreferences.SimulatorWindowRotationAngle = 0
            settings.DevicePreferences?[simulator.id] = devicePreferences
            
            if settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry == nil {
                settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry = .init()
            }
            
            let windowGeometry = settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry?[screenIdentifier] ?? .init()
            windowGeometry.WindowScale = scaleFactor
            windowGeometry.WindowCenter = center
            settings.DevicePreferences?[simulator.id]?.SimulatorWindowGeometry?[screenIdentifier] = windowGeometry
            
            executer.logger?.log(command: "Arranging simulator \(simulator.id) on \(executer.address) at location (\(center))")
            executer.logger?.log(output: "", statusCode: 0)
            
            #if DEBUG
                print("🔎 Arranging simulator \(simulator.id) on \(executer.address) at location (\(center))".bold)
            #endif
        }
        
        try simulatorProxy.storeSimulatorSettings(settings)
                
        let bootedSimulators = try simulatorProxy.bootedSimulators()
        for simulator in bootedSimulators {
            try simulatorProxy.terminateApp(identifier: configuration.buildBundleIdentifier, on: simulator)
            try simulatorProxy.terminateApp(identifier: configuration.testBundleIdentifier, on: simulator)
        }
        
        let unusedSimulators = bootedSimulators.filter { !simulators.contains($0) }
        for unusedSimulator in unusedSimulators {
            try simulatorProxy.shutdown(simulator: unusedSimulator)
        }
    }
        
    private func screenResolution(executer: Executer) throws -> (width: Int, height: Int) {
        let info = try executer.execute(#"system_profiler SPDisplaysDataType | grep "Resolution:""#)
        let resolution = try info.capturedGroups(withRegexString: #"Resolution: (\d+) x (\d+)"#).compactMap(Int.init)
        
        guard resolution.count == 2 else {
            throw Error("Failed extracting resolution", logger: executer.logger)
        }
        
        return (width: resolution[0], height: resolution[1])
    }
}
