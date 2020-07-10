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
                var WindowCenter: String? = nil
                var WindowScale: Double? = nil
            }

            var SimulatorExternalDisplay: Double? = nil
            var SimulatorWindowRotationAngle: Double? = nil
            var SimulatorWindowOrientation: String? = nil
            var SimulatorWindowGeometry: [String: DevicePreferences.WindowGeometry]? = nil
        }

        var ConnectHardwareKeyboard: Bool? = nil
        var AllowFullscreenMode: Bool? = nil
        var LocationMode: Double? = nil
        var SlowMotionAnimation: Bool? = nil
        var ShowChrome: Bool? = nil
        var ScreenConfigurations: [String: [String]]? = nil
        var PasteboardAutomaticSync: Bool? = nil
        var CurrentDeviceUDID: String? = nil
        var DevicePreferences: [String: Settings.DevicePreferences]? = nil
        var OptimizeRenderingForWindowScale: Bool? = nil
    }
}
