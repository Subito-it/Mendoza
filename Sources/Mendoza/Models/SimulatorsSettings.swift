//
//  SimulatorsSettings.swift
//  Mendoza
//
//  Created by Tomas Camin on 27/02/2019.
//

import Foundation

extension CommandLineProxy.Simulators {
    class Settings: Codable {
        class DevicePreferences: Codable {
            class WindowGeometry: Codable {
                var WindowCenter: String?
                var WindowScale: Double?
            }

            var SimulatorExternalDisplay: Double?
            var SimulatorWindowRotationAngle: Double?
            var SimulatorWindowOrientation: String?
            var SimulatorWindowGeometry: [String: DevicePreferences.WindowGeometry]?
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
