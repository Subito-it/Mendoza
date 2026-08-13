//
//  SimulatorSetupOperation+Arrangement.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

extension SimulatorSetupOperation {
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
    func updateSimulatorsSettings(executer: Executer, simulators: [Simulator], arrangeSimulators: Bool) throws -> Bool {
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

        let connectHardwareKeyboardFlag = true

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
}
