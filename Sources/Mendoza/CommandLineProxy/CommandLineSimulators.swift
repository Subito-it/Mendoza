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
            let commands = ["xcrun simctl delete all"]
            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }

        func reset() throws {
            try gracefullyQuit()

            let commands = ["osascript -e 'quit app \"$(xcode-select -p)/Applications/Simulator.app\"'",
                            "sleep 3"]
            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }

        func gracefullyQuit() throws {
            let commands = ["mendoza mendoza close_simulator_app",
                            "sleep 3",
                            "defaults read com.apple.iphonesimulator &>/dev/null"]

            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }

        func launch() throws {
            let commands = ["defaults read com.apple.iphonesimulator &>/dev/null",
                            "open -a \"$(xcode-select -p)/Applications/Simulator.app\"",
                            "sleep 3"]

            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }

        func rewriteSettingsIfNeeded() throws {
            let settings = try? loadSimulatorSettings()
            guard settings?.ScreenConfigurations?.keys.count != 1 else {
                return
            }

            let commands = ["defaults delete com.apple.iphonesimulator", // Delete iphone simulator settings to remove multiple `ScreenConfigurations` if present
                            "rm -rf '\(executer.homePath)/Library/Saved Application State/com.apple.iphonesimulator.savedState'"]
            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }

            try? launch()
            try? gracefullyQuit()
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

        func installRuntimeIfNeeded(_ runtime: String, nodeAddress: String, appleIdCredentials: Credentials?, administratorPassword: String?) throws {
            let isRuntimeInstalled: () throws -> Bool = { [unowned self] in
                let installedRuntimes = try self.executer.execute("xcrun simctl list runtimes")
                let escapedRuntime = runtime.replacingOccurrences(of: ".", with: "-")
                return installedRuntimes.contains("com.apple.CoreSimulator.SimRuntime.iOS-\(escapedRuntime)")
            }

            guard try !isRuntimeInstalled() else { return }

            guard let appleIdCredentials = appleIdCredentials,
                  let password = administratorPassword
            else {
                throw Error("Could not install simulator runtime on node `\(nodeAddress)` because administrator credentials were not provided. Please install `\(runtime)` runtime manually")
            }

            print("🦶 Installing runtime \(runtime) on node \(executer.address)".bold)

            let keychain = Keychain(executer: executer)
            try keychain.unlock(password: password)

            executer.logger?.addIgnoreList(password)
            executer.logger?.addIgnoreList(appleIdCredentials.username)
            executer.logger?.addIgnoreList(appleIdCredentials.password)

            try reset()

            let cmds = ["export FASTLANE_USER='\(appleIdCredentials.username)'",
                        "export FASTLANE_PASSWORD='\(appleIdCredentials.password)'",
                        "rm -f ~/Library/Caches/XcodeInstall/com.apple.pkg.iPhoneSimulatorSDK\(runtime.replacingOccurrences(of: ".", with: "_"))*.dmg",
                        "xcversion update",
                        "echo '\(password)' | sudo -S xcversion simulators --install='iOS \(runtime)'"]

            let result = try executer.capture(cmds.joined(separator: "; "))
            guard result.status == 0 else {
                _ = try executer.execute("rm -rf '\(executer.homePath)/Library/Caches/XcodeInstall/*.dmg'")
                throw Error("Failed installing runtime!", logger: executer.logger)
            }
            guard !result.output.contains("specified Apple developer account credentials are incorrect") else {
                throw Error("The provided Apple developer account credentials are incorrect. Please run `\(ConfigurationRootCommand().name!) \(ConfigurationAuthententicationUpdateCommand().name!)` command", logger: executer.logger) // swiftlint:disable:this force_unwrapping
            }
            guard try isRuntimeInstalled() else {
                throw Error("Failed installing runtime, after install simulator runtime still not installed!", logger: executer.logger)
            }
        }

        func disableSimulatorBezel() throws {
            _ = try executer.execute("defaults write com.apple.iphonesimulator FloatingNameMode 3")
            _ = try executer.execute("defaults write com.apple.iphonesimulator ShowChrome -bool false")
        }

        func enablePasteboardWorkaround() throws {
            // See https://twitter.com/objcandtwits/status/1227459913594658816?s=21
            _ = try executer.execute("defaults write com.apple.iphonesimulator PasteboardAutomaticSync -bool false")
        }

        func enableLowQualityGraphicOverrides() throws {
            _ = try executer.execute("defaults write com.apple.iphonesimulator GraphicsQualityOverride 10")
        }

        func enableXcode11ReleaseNotesWorkarounds(on simulator: Simulator) throws {
            // See release notes workarounds: https://developer.apple.com/documentation/xcode_release_notes/xcode_11_release_notes?language=objc
            // These settings are hot loaded no reboot of the device is necessary
            _ = try? executer.execute("xcrun simctl spawn '\(simulator.id)' defaults write com.apple.springboard FBLaunchWatchdogScale 2")
        }

        func enableXcode13Workarounds(on simulator: Simulator) throws {
            // See https://developer.apple.com/forums/thread/683277?answerId=682047022#682047022
            let path = "\(simulatorSettingsPath(for: simulator))/com.apple.suggestions.plist"
            _ = try? executer.execute("plutil -replace SuggestionsAppLibraryEnabled -bool NO '\(path)'")
        }

        func disableSlideToType(on simulator: Simulator) throws {
            let numberFormatter = NumberFormatter()
            numberFormatter.decimalSeparator = "."
            let deviceVersion = numberFormatter.number(from: simulator.device.runtime)?.floatValue ?? 0.0

            if deviceVersion >= 13.0 {
                // These settings are hot loaded no reboot of the device is necessary
                _ = try executer.execute("xcrun simctl spawn '\(simulator.id)' defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true")
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

        func rawSimulatorStatus() throws -> String {
            try executer.execute("xcrun xctrace list devices")
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
            let simulatorsStatus = try cachedSimulatorStatus ?? (try rawSimulatorStatus())

            let statusRegex = try NSRegularExpression(pattern: #"(.*?)\s(Simulator\s)?\((.*)\)\s\((.*)\)$"#)
            
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

            let devicesType = try executer.execute("xcrun simctl list devicetypes")

            let deviceRegex = try NSRegularExpression(pattern: #"\#(device.name) \(com.apple.CoreSimulator.SimDeviceType.(.*)\)$"#)
            for deviceType in devicesType.components(separatedBy: "\n") {
                let captureGroups = deviceType.capturedGroups(regex: deviceRegex)

                guard captureGroups.count == 1 else { continue }

                let deviceIdentifier = "com.apple.CoreSimulator.SimDeviceType." + captureGroups[0]
                let runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-" + device.runtime.replacingOccurrences(of: ".", with: "-")

                let simulatorIdentifier = try executer.execute("xcrun simctl create '\(name)' \(deviceIdentifier) \(runtimeIdentifier)")

                return Simulator(id: simulatorIdentifier, name: name, device: device)
            }

            throw Error("Failed making Simulator", logger: executer.logger)
        }

        func installedSimulators(cachedSimulatorStatus: String? = nil) throws -> [Simulator] {
            let simulatorsStatus = try cachedSimulatorStatus ?? (try rawSimulatorStatus())

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
            let availableStatuses = try executer.execute("xcrun simctl list devices")
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

                guard let data = try? Data(contentsOf: uniqueUrl) else { return nil }

                return try? PropertyListDecoder().decode(Simulators.Settings.self, from: data)
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
            _ = try executer.execute("defaults read com.apple.iphonesimulator &>/dev/null")
        }

        private func simulatorSettingsPath(for simulator: Simulator) -> String {
            "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/Preferences"
        }
    }
}
