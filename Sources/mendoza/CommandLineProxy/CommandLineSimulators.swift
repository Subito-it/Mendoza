//
//  CommandLineSimulators.swift
//  Mendoza
//
//  Created by Tomas Camin on 31/01/2019.
//

import Foundation

extension CommandLineProxy {
    class Simulators {
        var settingsPath: String { "\(executer.homePath)/Library/Preferences/com.apple.iphonesimulator.plist" }

        private var executer: Executer
        private let verbose: Bool

        init(executer: Executer, verbose: Bool) {
            self.executer = executer
            self.verbose = verbose
        }

        func deleteAll() throws {
            _ = try? executer.execute(#"for pid in $(lsof | grep -E "/Users/.*/Library/Developer/CoreSimulator" | awk '{print $2}'); do kill -9 $pid; done"#)
            _ = try? executer.execute("killall -9 com.apple.CoreSimulator.CoreSimulatorService")
            Thread.sleep(forTimeInterval: 5.0)
            _ = try? executer.execute("rm -rf ~/Library/Developer/CoreSimulator")
            _ = try? executer.execute("killall -9 com.apple.CoreSimulator.CoreSimulatorService")
        }

        func reset() throws {
            try gracefullyQuit()

            let commands = ["osascript -e 'quit app \"Simulator.app\"'", // we don't prefix $(xcode-select -p) since another version of the simulator might be running
                            "sleep 3"]
            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }

        func gracefullyQuit() throws {
            let commands = ["defaults read com.apple.iphonesimulator &>/dev/null", // This (unexpectedly) ensures that settings in ~/Library/Preferences/com.apple.iphonesimulator.plist get reloaded
                            "mendoza mendoza close_simulator_app",
                            "sleep 3"]

            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }

        func launch() throws {
            let commands = ["defaults read com.apple.iphonesimulator &>/dev/null", // This (unexpectedly) ensures that settings in ~/Library/Preferences/com.apple.iphonesimulator.plist get reloaded
                            "open -a \"$(xcode-select -p)/Applications/Simulator.app\"",
                            "sleep 3"]

            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }

        func deleteSettingsIfNeeded() throws -> Bool {
            let settings = try? loadSimulatorSettings()
            guard settings?.ScreenConfigurations?.keys.count != 1 else {
                return false
            }

            let commands = ["defaults delete com.apple.iphonesimulator", // Delete iphone simulator settings to remove multiple `ScreenConfigurations` if present
                            "rm -rf '\(executer.homePath)/Library/Saved Application State/com.apple.iphonesimulator.savedState'"]
            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }

            return true
        }

        func shutdownAll() throws {
            _ = try executer.execute("xcrun simctl shutdown all")
        }

        func shutdown(simulator: Simulator) throws {
            _ = try executer.execute("xcrun simctl shutdown \(simulator.id)")
        }

        func launchApp(identifier: String, on simulator: Simulator) throws {
            _ = try executer.execute("xcrun simctl launch \(simulator.id) \(identifier)")
        }

        func terminateApp(identifier: String, on simulator: Simulator) throws {
            _ = try executer.execute("xcrun simctl terminate \(simulator.id) \(identifier)")
        }

        func checkIfRuntimeInstalled(_ runtime: String, nodeAddress: String) throws {
            let isRuntimeInstalled: () throws -> Bool = { [unowned self] in
                let installedRuntimes = try self.executer.execute("xcrun simctl list runtimes 2>/dev/null")
                let escapedRuntime = runtime.replacingOccurrences(of: ".", with: "-")
                return installedRuntimes.contains("com.apple.CoreSimulator.SimRuntime.iOS-\(escapedRuntime)")
            }

            guard try !isRuntimeInstalled() else { return }

            throw Error("You'll need to manually install \(runtime) on remote node \(nodeAddress)", logger: executer.logger)
        }

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
            let paths = [
                "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/UserSettings.plist",
                "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/UserConfigurationProfiles/EffectiveUserSettings.plist",
                "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/UserConfigurationProfiles/PublicInfo/PublicEffectiveUserSettings.plist",
            ]

            var updates = [Bool]()
            for path in paths {
                try updates.append(updatePlistIfNeeded(path: path, key: "restrictedBool.allowPasswordAutoFill.value", value: false))
            }

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

        func rawSimulatorStatus() throws -> String {
            try executer.execute("xcrun xctrace list devices 2>/dev/null")
        }

        /// This method instantiates a Simulator given a name.
        ///
        /// - Note: The simulator is created if necessary
        ///
        /// - Parameters:
        ///   - name: name of the device to create (e.g 'iPhone 6-1')
        ///   - device: the device instance to create
        /// - Returns: an instance of Simulator
        func makeSimulatorIfNeeded(name: String, device: Device, cachedSimulatorStatus: String? = nil) throws -> Simulator {
            // We use 'instruments -s devices' instead of 'xcrun simctl list devices' because it gives more complete infos including simulator version
            let simulatorsStatus = try cachedSimulatorStatus ?? rawSimulatorStatus()

            let statusRegex = try NSRegularExpression(pattern: #"(.*?)\s(Simulator\s)?\((\d+\.\d+(?:\.\d+)?)\)\s\(([0-9a-fA-F-]+)\)$"#)

            let simulatorStatus: (String) -> (String, String, String)? = { rawStatus in
                let captureGroups = rawStatus.capturedGroups(regex: statusRegex)

                guard captureGroups.count == 4 else { return nil }

                return (captureGroups[0], captureGroups[2], captureGroups[3])
            }

            for rawStatus in simulatorsStatus.components(separatedBy: "\n") {
                if let (simulatorName, simulatorRuntime, simulatorId) = simulatorStatus(rawStatus) {
                    if simulatorName == name, simulatorRuntime == device.runtime {
                        return Simulator(id: simulatorId, name: name, device: device)
                    }
                }
            }

            // Some versions of Xcode add a minor to simulator version (e.g 14.0.1 instead of 14.0)
            for rawStatus in simulatorsStatus.components(separatedBy: "\n") {
                if let (simulatorName, simulatorRuntime, simulatorId) = simulatorStatus(rawStatus) {
                    if simulatorName == name, simulatorRuntime.hasPrefix(device.runtime) {
                        print("📱  Simulator \(name) using version \(simulatorRuntime) instead of \(device.runtime)")

                        return Simulator(id: simulatorId, name: name, device: device)
                    }
                }
            }

            #if DEBUG
                print("📱  Simulator \(name) not found, creating a new one on \(executer.address)")
            #endif

            // Simulator not found

            let devicesType = try executer.execute("xcrun simctl list devicetypes 2>/dev/null")

            // Escape parentheses in device name to avoid treating them as regex capture groups
            let sanitizedDeviceName = device.name
                .replacingOccurrences(of: "(", with: "\\(")
                .replacingOccurrences(of: ")", with: "\\)")
            let deviceRegex = try NSRegularExpression(pattern: #"\#(sanitizedDeviceName) \(com.apple.CoreSimulator.SimDeviceType.(.*)\)$"#)
            for deviceType in devicesType.components(separatedBy: "\n") {
                let captureGroups = deviceType.capturedGroups(regex: deviceRegex)

                guard captureGroups.count == 1 else { continue }

                let deviceIdentifier = "com.apple.CoreSimulator.SimDeviceType." + captureGroups[0]
                let runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-" + device.runtime.replacingOccurrences(of: ".", with: "-")

                let simulatorIdentifier = try executer.execute("xcrun simctl create '\(name)' \(deviceIdentifier) \(runtimeIdentifier) 2>/dev/null")

                return Simulator(id: simulatorIdentifier, name: name, device: device)
            }

            throw Error("Failed making Simulator", logger: executer.logger)
        }

        func installedSimulators(cachedSimulatorStatus: String? = nil) throws -> [Simulator] {
            let simulatorsStatus = try cachedSimulatorStatus ?? rawSimulatorStatus()

            var simulators = [Simulator]()
            for status in simulatorsStatus.components(separatedBy: "\n") {
                let capture = try status.capturedGroups(withRegexString: #"(.*) \((.*)\) \((.*)\)"#)

                guard capture.count == 3 else { continue }

                simulators.append(Simulator(id: capture[2], name: capture[0], device: Device(name: capture[0], runtime: capture[1], language: nil, locale: nil)))
            }

            return simulators
        }

        func bootedSimulators() throws -> [Simulator] {
            let installed = try installedSimulators()

            var simulators = [Simulator]()
            let availableStatuses = try executer.execute("xcrun simctl list devices 2>/dev/null")
            for status in availableStatuses.components(separatedBy: "\n") {
                let capture = try status.capturedGroups(withRegexString: #"(.*) \((.*)\) \((.*)\)"#)

                guard capture.count == 3 else { continue }

                let simulatorStatus = capture[2]
                guard simulatorStatus == "Booted" else { continue }

                if let simulator = installed.first(where: { $0.id == capture[1] }) {
                    simulators.append(simulator)
                }
            }

            return simulators
        }

        func boot(simulator: Simulator) throws {
            _ = try executer.execute("xcrun simctl boot '\(simulator.id)' || true")
        }

        func waitForBoot(simulator: Simulator) throws {
            _ = try executer.execute("xcrun simctl bootstatus '\(simulator.id)'")
        }

        func bootSynchronously(simulator: Simulator) throws {
            // https://gist.github.com/keith/33d3e28de4217f3baecde15357bfe5f6
            // boot and synchronously wait for device to boot
            _ = try executer.execute("xcrun simctl bootstatus '\(simulator.id)' -b || true")

            Thread.sleep(forTimeInterval: 5.0)
        }

        func loadSimulatorSettings() throws -> Simulators.Settings {
            let loadSettings: () throws -> Simulators.Settings? = {
                let uniqueUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).plist")
                try self.executer.download(remotePath: self.settingsPath, localUrl: uniqueUrl)

                let data = try Data(contentsOf: uniqueUrl)

                return try PropertyListDecoder().decode(Simulators.Settings.self, from: data)
            }

            var settings: Simulators.Settings?
            if try executer.fileExists(atPath: settingsPath) {
                settings = try? loadSettings()
            }

            guard let result = settings else {
                throw Error("Failed loading simulator plist", logger: executer.logger)
            }

            return result
        }

        func storeSimulatorSettings(_ settings: Simulators.Settings) throws {
            let data = try PropertyListEncoder().encode(settings)
            let uniqueUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).plist")
            try data.write(to: uniqueUrl)

            _ = try executer.execute("rm '\(settingsPath)'")
            try executer.upload(localUrl: uniqueUrl, remotePath: settingsPath)

            // Force reload
            _ = try executer.execute("rm -rf '\(executer.homePath)/Library/Saved Application State/com.apple.iphonesimulator.savedState'")
        }

        private func simulatorSettingsPath(for simulator: Simulator) -> String {
            "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/Preferences"
        }

        private func updateSimulatorDefaults(key: String, value: Bool) throws -> Bool {
            _ = try executer.execute("defaults write com.apple.iphonesimulator \(key) -bool \(value ? "true" : "false")")

            return false
        }

        private func updateSimulatorDefaults(key: String, value: Int) throws -> Bool {
            _ = try executer.execute("defaults write com.apple.iphonesimulator \(key) \(value)")

            return false
        }

        private func updatePlistIfNeeded(path: String, key: String, value: Bool) throws -> Bool {
            if try executer.execute("ls '\(path)' &>/dev/null && plutil -extract \(key) raw '\(path)' || true") != (value ? "true" : "false") {
                _ = try? executer.execute("plutil -replace \(key) -bool \(value ? "YES" : "NO") '\(path)'")
                return true
            }

            return false
        }

        private func updatePlistIfNeeded(path: String, key: String, value: Int) throws -> Bool {
            if try executer.execute("ls '\(path)' &>/dev/null && plutil -extract \(key) raw '\(path)' || true") != value.description {
                _ = try? executer.execute("plutil -replace \(key) -integer \(value.description) '\(path)'")
                return true
            }

            return false
        }
    }
}
