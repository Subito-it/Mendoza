//
//  CoreSimulatorProxy.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/08/2026.
//

import Foundation

/// Thin reflection based wrapper around the private `CoreSimulator.framework`.
///
/// Xcode 27 replaced Simulator.app with DeviceHub, which never attaches to simulators booted via
/// `simctl` (Apple known issue 176809181). Settings that used to be applied by writing to the
/// `com.apple.iphonesimulator` host plist are therefore ignored. The equivalent knobs live on
/// `SimDevice` inside CoreSimulator, which is shared by every Xcode version and works headless.
///
/// - Important: This is a private API. Every selector is looked up dynamically and a missing one is
///              reported as `.unavailable` rather than crashing, so a future Xcode that renames or
///              removes a selector degrades instead of taking the whole test run down.
/// - Note: Must run *on the node owning the simulator* — CoreSimulator is not reachable over SSH.
///         Callers go through `mendoza mendoza coresimulator …` so this holds for remote nodes too.
enum CoreSimulatorProxy {
    enum Result: Equatable {
        case success
        /// The selector does not exist in this Xcode's CoreSimulator.
        case unavailable
        case failure(String)
    }

    private static let frameworkPath = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework"

    /// Setting to apply to a booted simulator.
    enum Setting {
        /// `false` makes iOS show the on-screen software keyboard, which UI tests that type into
        /// text fields depend on. Replaces the legacy `ConnectHardwareKeyboard` plist key.
        case hardwareKeyboard(enabled: Bool)
        /// Suppresses the Dynamic Island, which can overlay hittable elements on newer devices.
        case dynamicIslandSuppressed(Bool)
        case increaseContrast(enabled: Bool)
        /// Keeps the display awake. Simulators that sleep make tests fail on unhittable elements.
        case displayBacklight(active: Bool)
        /// Pins the status bar clock, useful to keep screenshots stable.
        case statusBarTime(String)

        var name: String {
            switch self {
            case .hardwareKeyboard: return "hardware_keyboard"
            case .dynamicIslandSuppressed: return "dynamic_island_suppressed"
            case .increaseContrast: return "increase_contrast"
            case .displayBacklight: return "display_backlight"
            case .statusBarTime: return "status_bar_time"
            }
        }

        /// Parses the `key=value` form used on the command line.
        init?(rawValue: String) {
            let components = rawValue.components(separatedBy: "=")
            guard components.count == 2 else { return nil }

            let value = components[1]
            let flag = ["1", "true", "yes", "on"].contains(value.lowercased())

            switch components[0] {
            case "hardware_keyboard": self = .hardwareKeyboard(enabled: flag)
            case "dynamic_island_suppressed": self = .dynamicIslandSuppressed(flag)
            case "increase_contrast": self = .increaseContrast(enabled: flag)
            case "display_backlight": self = .displayBacklight(active: flag)
            case "status_bar_time": self = .statusBarTime(value)
            default: return nil
            }
        }
    }

    static func apply(_ setting: Setting, deviceIdentifier: String, developerDir: String) -> Result {
        guard let device = device(identifier: deviceIdentifier, developerDir: developerDir) else {
            return .failure("Simulator \(deviceIdentifier) not found")
        }

        switch setting {
        case let .hardwareKeyboard(enabled):
            // Second parameter is the keyboard type, 0 is the default layout
            return invoke(device, "setHardwareKeyboardEnabled:keyboardType:error:", flag: enabled, keyboardType: 0)
        case let .dynamicIslandSuppressed(suppressed):
            return invoke(device, "setDynamicIslandSuppressed:error:", flag: suppressed)
        case let .increaseContrast(enabled):
            return invoke(device, "setIncreaseContrastEnabled:error:", flag: enabled)
        case let .displayBacklight(active):
            return invoke(device, "setDisplayBacklightActive:error:", flag: active)
        case let .statusBarTime(time):
            return invoke(device, "overrideStatusBarTimeString:error:", string: time)
        }
    }

    // MARK: - Device lookup

    static func device(identifier: String, developerDir: String) -> AnyObject? {
        devices(developerDir: developerDir).first { device in
            Self.identifier(of: device)?.caseInsensitiveCompare(identifier) == .orderedSame
        }
    }

    /// All devices in the default device set, booted or not.
    static func devices(developerDir: String) -> [AnyObject] {
        guard let bundle = Bundle(path: frameworkPath), bundle.load() else { return [] }
        guard let contextClass = NSClassFromString("SimServiceContext") as AnyObject? else { return [] }

        guard let context = contextClass
            .perform(NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"), with: developerDir, with: nil)?
            .takeUnretainedValue() else { return [] }

        guard let deviceSet = context
            .perform(NSSelectorFromString("defaultDeviceSetWithError:"), with: nil)?
            .takeUnretainedValue() else { return [] }

        return deviceSet.perform(NSSelectorFromString("devices"))?.takeUnretainedValue() as? [AnyObject] ?? []
    }

    static func identifier(of device: AnyObject) -> String? {
        (device.perform(NSSelectorFromString("UDID"))?.takeUnretainedValue() as? NSUUID)?.uuidString
    }

    static func name(of device: AnyObject) -> String? {
        device.perform(NSSelectorFromString("name"))?.takeUnretainedValue() as? String
    }

    /// `state` returns a primitive, so it cannot go through `perform` without crashing.
    /// 3 is `SimDeviceStateBooted`.
    static func isBooted(_ device: AnyObject) -> Bool {
        let selector = NSSelectorFromString("state")
        guard let method = class_getInstanceMethod(object_getClass(device), selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector) -> UInt64
        return unsafeBitCast(method_getImplementation(method), to: Function.self)(device, selector) == 3
    }

    // MARK: - Dynamic invocation

    private static func invoke(_ device: AnyObject, _ selectorName: String, flag: Bool, keyboardType: UInt8? = nil) -> Result {
        let selector = NSSelectorFromString(selectorName)
        guard device.responds(to: selector),
              let method = class_getInstanceMethod(object_getClass(device), selector)
        else {
            return .unavailable
        }

        var error: AnyObject?
        let succeeded: Bool

        if let keyboardType {
            // Type encoding is B32@0:8B16C20^@24, so keyboardType is an unsigned char
            typealias Function = @convention(c) (AnyObject, Selector, ObjCBool, UInt8, UnsafeMutablePointer<AnyObject?>?) -> ObjCBool
            let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
            succeeded = withUnsafeMutablePointer(to: &error) { function(device, selector, ObjCBool(flag), keyboardType, $0) }.boolValue
        } else {
            typealias Function = @convention(c) (AnyObject, Selector, ObjCBool, UnsafeMutablePointer<AnyObject?>?) -> ObjCBool
            let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
            succeeded = withUnsafeMutablePointer(to: &error) { function(device, selector, ObjCBool(flag), $0) }.boolValue
        }

        return succeeded ? .success : .failure(describe(error))
    }

    private static func invoke(_ device: AnyObject, _ selectorName: String, string: String) -> Result {
        let selector = NSSelectorFromString(selectorName)
        guard device.responds(to: selector),
              let method = class_getInstanceMethod(object_getClass(device), selector)
        else {
            return .unavailable
        }

        typealias Function = @convention(c) (AnyObject, Selector, NSString, UnsafeMutablePointer<AnyObject?>?) -> ObjCBool
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)

        var error: AnyObject?
        let succeeded = withUnsafeMutablePointer(to: &error) { function(device, selector, string as NSString, $0) }.boolValue

        return succeeded ? .success : .failure(describe(error))
    }

    private static func describe(_ error: AnyObject?) -> String {
        (error as? NSError)?.localizedDescription ?? "unknown error"
    }
}
