//
//  SimulatorsSettings.swift
//  Mendoza
//
//  Created by Tomas Camin on 27/02/2019.
//

import Foundation

extension CommandLineProxy.Simulators {
    class Settings: Codable {
        class DevicePreferences: Codable, Equatable {
            static func == (lhs: CommandLineProxy.Simulators.Settings.DevicePreferences, rhs: CommandLineProxy.Simulators.Settings.DevicePreferences) -> Bool {
                lhs.SimulatorWindowGeometry == rhs.SimulatorWindowGeometry &&
                    lhs.SimulatorWindowOrientation == rhs.SimulatorWindowOrientation &&
                    lhs.ConnectHardwareKeyboard == rhs.ConnectHardwareKeyboard &&
                    lhs.SimulatorWindowRotationAngle == rhs.SimulatorWindowRotationAngle &&
                    lhs.SimulatorExternalDisplay == rhs.SimulatorExternalDisplay
            }

            class WindowGeometry: Codable, Equatable {
                static func == (lhs: CommandLineProxy.Simulators.Settings.DevicePreferences.WindowGeometry, rhs: CommandLineProxy.Simulators.Settings.DevicePreferences.WindowGeometry) -> Bool {
                    lhs.WindowCenter == rhs.WindowCenter && lhs.WindowScale == rhs.WindowScale
                }

                var WindowCenter: String?
                var WindowScale: Double?
            }

            var SimulatorExternalDisplay: Double?
            var SimulatorWindowRotationAngle: Double?
            var SimulatorWindowOrientation: String?
            var SimulatorWindowGeometry: [String: DevicePreferences.WindowGeometry]?
            var ConnectHardwareKeyboard: Bool?
        }

        var ConnectHardwareKeyboard: Bool?
        var AllowFullscreenMode: Bool?
        var LocationMode: Double?
        var SlowMotionAnimation: Bool?
        var ShowChrome: Bool?
        var ScreenConfigurations: [String: [String]]?
        var PasteboardAutomaticSync: Bool?
        var CurrentDeviceUDID: String?
        var DevicePreferences: [String: Settings.DevicePreferences]?
        var OptimizeRenderingForWindowScale: Bool?
    }
}
