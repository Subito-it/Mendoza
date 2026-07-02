//
//  CommandLineSimulators+Workarounds.swift
//  Mendoza
//
//  Created by Tomas Camin on 31/01/2019.
//

import Foundation

extension CommandLineProxy.Simulators {
    func disableSimulatorBezel() throws -> Bool {
        var updates = [Bool]()
        try updates.append(updateSimulatorDefaults(key: "FloatingNameMode", value: 3))
        try updates.append(updateSimulatorDefaults(key: "ShowChrome", value: false))
        return updates.contains(true)
    }

    func enablePasteboardWorkaround() throws -> Bool {
        try updateSimulatorDefaults(key: "PasteboardAutomaticSync", value: false)
    }

    func enableLowQualityGraphicOverrides() throws -> Bool {
        try updateSimulatorDefaults(key: "GraphicsQualityOverride", value: 10)
    }

    func enableXcode13Workarounds(on simulator: Simulator) throws -> Bool {
        // See https://developer.apple.com/forums/thread/683277?answerId=682047022#682047022
        let path = "\(simulatorSettingsPath(for: simulator))/com.apple.suggestions.plist"
        return try updatePlistIfNeeded(path: path, key: "SuggestionsAppLibraryEnabled", value: false)
    }

    func disablePasswordAutofill(on simulator: Simulator) throws -> Bool {
        try updatePasswordAutofill(on: simulator, enabled: false)
    }

    func enablePasswordAutofill(on simulator: Simulator) throws -> Bool {
        try updatePasswordAutofill(on: simulator, enabled: true)
    }

    private func updatePasswordAutofill(on simulator: Simulator, enabled: Bool) throws -> Bool {
        let configProfilePaths = [
            "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/UserSettings.plist",
            "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/UserConfigurationProfiles/EffectiveUserSettings.plist",
            "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/UserConfigurationProfiles/PublicInfo/PublicEffectiveUserSettings.plist"
        ]

        var updates = [Bool]()
        for path in configProfilePaths {
            try updates.append(updatePlistIfNeeded(path: path, key: "restrictedBool.allowPasswordAutoFill.value", value: enabled))
            try updates.append(updatePlistIfNeeded(path: path, key: "restrictedBool.allowPasswordAutoFill.ask", value: false))
        }

        let webUIPath = "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/Preferences/com.apple.WebUI.plist"
        try updates.append(updatePlistIfNeeded(path: webUIPath, key: "AutoFillPasswords", value: enabled))

        return updates.contains(true)
    }

    func enableXcode11ReleaseNotesWorkarounds(on simulator: Simulator) {
        // See release notes workarounds: https://developer.apple.com/documentation/xcode_release_notes/xcode_11_release_notes?language=objc
        // These settings are hot loaded no reboot of the device is necessary
        _ = try? executer.execute("xcrun simctl spawn '\(simulator.id)' defaults write com.apple.springboard FBLaunchWatchdogScale 2")
    }

    func disableSlideToType(on simulator: Simulator) {
        let numberFormatter = NumberFormatter()
        numberFormatter.decimalSeparator = "."
        let deviceVersion = numberFormatter.number(from: simulator.device.runtime)?.floatValue ?? 0.0

        if deviceVersion >= 13.0 {
            // These settings are hot loaded no reboot of the device is necessary
            _ = try? executer.execute("xcrun simctl spawn '\(simulator.id)' defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true")
        }
    }

    func disableMultilingualKeyboardTip(on simulator: Simulator) {
        let numberFormatter = NumberFormatter()
        numberFormatter.decimalSeparator = "."
        let deviceVersion = numberFormatter.number(from: simulator.device.runtime)?.floatValue ?? 0.0

        if deviceVersion >= 26.0 {
            // These settings are hot loaded no reboot of the device is necessary
            _ = try? executer.execute("xcrun simctl spawn '\(simulator.id)' defaults write com.apple.keyboard.preferences MultilingualKeyboardTip -bool true")
        }
    }

    func disableSafariMenuOnboarding(on simulator: Simulator) {
        let numberFormatter = NumberFormatter()
        numberFormatter.decimalSeparator = "."
        let deviceVersion = numberFormatter.number(from: simulator.device.runtime)?.floatValue ?? 0.0

        if deviceVersion >= 26.0 {
            _ = try? executer.execute(#"xcrun simctl spawn '"# + simulator.id + #"' defaults write com.apple.mobilesafari WBSOnboardingStatesDefaultsKeyV0.2 -dict "CustomizeStartPage" -int 1 "EnableCloudSync" -int 1 "EnableHighlights" -int 2 "ExtensionsDiscovery" -int 1 "SetDefaultBrowser" -int 2 "TipForMoreButton" -int 3"#)
        }
    }

    func updateLanguage(on simulator: Simulator, language: String?, locale: String?) throws -> Bool {
        let path = "\(simulatorSettingsPath(for: simulator))/.GlobalPreferences.plist"

        if try executer.execute("ls '\(path)' 2>/dev/null | wc -l") == "0" {
            let tmpPath = Path.temp.url.appendingPathComponent("\(UUID().uuidString).plist").path

            var json = [String]()
            if let language = language {
                guard language.components(separatedBy: "-").count == 2 else {
                    throw Error("Invalid language provided \(language), expecting", logger: executer.logger)
                }
                json.append("\"AppleLanguages\":[\"\(language)\"]")
            }
            if let locale = locale {
                guard locale.components(separatedBy: "_").count == 2 else {
                    throw Error("Invalid locale provided \(locale), expecting _", logger: executer.logger)
                }
                json.append("\"AppleLocale\": \"\(locale)\"")
            }

            if json.count > 0 {
                _ = try executer.execute("echo '{ \(json.joined(separator: ", ")) }' > \(tmpPath); plutil -convert binary1 \(tmpPath) -o \(path)")
            }

            return json.count > 0
        } else {
            let currentLanguage = try executer.execute(#"plutil -extract AppleLanguages xml1 -o - '\#(path)' | sed -n "s/.*<string>\(.*\)<\/string>.*/\1/p" | head -n 1"#)
            let currentLocale = try executer.execute(#"plutil -extract AppleLocale xml1 -o - '\#(path)' | sed -n "s/.*<string>\(.*\)<\/string>.*/\1/p" | head -n 1"#)

            if let language = language {
                guard language.components(separatedBy: "-").count == 2 else {
                    throw Error("Invalid language provided \(language), expecting", logger: executer.logger)
                }
                _ = try executer.execute(#"plutil -replace AppleLanguages -json '[ "\#(language)" ]' \#(path)"#)
            }
            if let locale = locale {
                guard locale.components(separatedBy: "_").count == 2 else {
                    throw Error("Invalid locale provided \(locale), expecting _", logger: executer.logger)
                }
                _ = try executer.execute(#"plutil -replace AppleLocale -json '"\#(locale)"' \#(path)"#)
            }

            return currentLocale != (locale ?? currentLocale) || currentLanguage != (language ?? currentLanguage)
        }
    }

    func increaseWatchdogExceptionTimeout(on simulator: Simulator, appBundleIndentifier: String, testBundleIdentifier: String, timeout: Int = 120) throws -> Bool {
        let path = "\(simulatorSettingsPath(for: simulator))/com.apple.springboard.plist"
        let identifiers = [appBundleIndentifier, testBundleIdentifier]

        var updates = [Bool]()
        for identifier in identifiers {
            let key = "FBLaunchWatchdogExceptions.\(identifier.replacingOccurrences(of: ".", with: #"\\"#))"

            try updates.append(updatePlistIfNeeded(path: path, key: key, value: timeout))
        }

        return updates.contains(true)
    }
}
