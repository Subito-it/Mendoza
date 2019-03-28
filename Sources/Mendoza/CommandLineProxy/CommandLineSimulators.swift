//
//  CommandLineSimulators.swift
//  Mendoza
//
//  Created by Tomas Camin on 31/01/2019.
//

import Foundation

extension CommandLineProxy {
    class Simulators {
        var settingsPath: String { return "\(executer.homePath)/Library/Preferences/com.apple.iphonesimulator.plist" }
        
        private var executer: Executer
        
        init(executer: Executer) {
            self.executer = executer
        }
        
        func wakeUp() throws {
            _ = try executer.execute("open -a \"$(xcode-select -p)/Applications/Simulator.app\"")
        }
                
        func reset() throws {
            let commands = ["killall -9 com.apple.CoreSimulator.CoreSimulatorService",
                            "pkill Simulator",
                            "sleep 5",
                            "open -a \"$(xcode-select -p)/Applications/Simulator.app\"",
                            "sleep 15",
                            "killall -9 com.apple.CoreSimulator.CoreSimulatorService",
                            "pkill Simulator",
                            "rm -rf '\(executer.homePath)/Library/Saved Application State/com.apple.iphonesimulator.savedState'",
                            "sleep 5",
                            "defaults read com.apple.iphonesimulator &>/dev/null"]
            
            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }
        
        func forceSettingsRewrite() throws {
            let commands = ["open -a \"$(xcode-select -p)/Applications/Simulator.app\"",
                            "sleep 15",
                            "killall -9 com.apple.CoreSimulator.CoreSimulatorService",
                            "pkill Simulator",
                            "rm -rf '\(executer.homePath)/Library/Saved Application State/com.apple.iphonesimulator.savedState'",
                            "sleep 5",
                            "open -a \"$(xcode-select -p)/Applications/Simulator.app\"",
                            "sleep 15",
                            "killall -9 com.apple.CoreSimulator.CoreSimulatorService",
                            "pkill Simulator",
                            "defaults read com.apple.iphonesimulator"]
            
            try commands.forEach { _ = try executer.execute("\($0) 2>/dev/null || true") }
        }
        
        func shutdown(simulator: Simulator) throws {
            _ = try executer.execute("xcrun simctl shutdown \(simulator.id)")
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
            
            guard let appleIdCredentials = appleIdCredentials
                , let password = administratorPassword else {
                throw Error("Could not install simulator runtime on node `\(nodeAddress)` because administrator credentials were not provided. Please install `\(runtime)` runtime manually")
            }

            print("🦶 Installing runtime \(runtime) on node \(executer.address)".bold)

            let keychain = Keychain(executer: executer)
            try keychain.unlock(password: password)

            executer.logger?.addBlackList(password)
            executer.logger?.addBlackList(appleIdCredentials.username)
            executer.logger?.addBlackList(appleIdCredentials.password)
            
            let cmds = ["export PATH=/usr/bin:/usr/local/bin:/usr/sbin:/sbin",
                        "export FASTLANE_USER=\(appleIdCredentials.username)",
                        "export FASTLANE_PASSWORD=\(appleIdCredentials.password)",
                        "xcversion update",
                        "echo '\(password)' | sudo -S xcversion simulators --install='iOS \(runtime)'",
                        "killall -9 com.apple.CoreSimulator.CoreSimulatorService"]
            
            let result = try executer.capture(cmds.joined(separator: "; "))
            guard result.status == 0 else {
                _ = try executer.execute("rm -rf \(executer.homePath)/Library/Caches/XcodeInstall/*.dmg")
                throw Error("Failed installing runtime!", logger: executer.logger)
            }
            guard !result.output.contains("specified Apple developer account credentials are incorrect") else {
                throw Error("The provided Apple developer account credentials are incorrect. Please run `\(ConfigurationRootCommand().name!) \(ConfigurationAuthententicationUpdateCommand().name!)` command", logger: executer.logger)
            }
            guard try isRuntimeInstalled() else {
                throw Error("Failed installing runtime, after install simulator runtime still not installed!", logger: executer.logger)
            }
        }

        /// This method instantiates a Simulator given a name.
        ///
        /// - Note: The simulator is created if necessary
        ///
        /// - Parameters:
        ///   - name: name of the device to create (e.g 'iPhone 6-1')
        ///   - device: the device instance to create
        /// - Returns: an instance of Simulator
        func makeSimulatorIfNeeded(name: String, device: Device) throws -> Simulator {            
            let simulatorsStatus = try executer.execute("$(xcode-select -p)/usr/bin/instruments -s devices")
            
            let statusRegex = try NSRegularExpression(pattern: #"(.*)\s\((\d+\.\d+(\.\d+)?)\)\s\[(.*)\]\s\(Simulator\)$"#)
            for simulatorStatus in simulatorsStatus.components(separatedBy: "\n") {
                let captureGroups = simulatorStatus.capturedGroups(regex: statusRegex)
                
                guard captureGroups.count == 4 else { continue }
                
                let simulatorName = captureGroups[0]
                let simulatorRuntime = captureGroups[1]
                let simulatorId = captureGroups[3]
                
                if simulatorName == name, simulatorRuntime == device.runtime {
                    return Simulator(id: simulatorId, name: name, device: device)
                }
            }
            
            #if DEBUG
                print("📱  Simulator \(name) not found, creating a new one")
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
        
        func installedSimulators() throws -> [Simulator] {
            let simulatorsStatus = try executer.execute("$(xcode-select -p)/usr/bin/instruments -s devices")
            
            var simulators = [Simulator]()
            for status in simulatorsStatus.components(separatedBy: "\n") {
                let capture = try status.capturedGroups(withRegexString: #"(.*) \((.*)\) \[(.*)\] \(Simulator\)"#)
                
                guard capture.count == 3 else { continue }
                
                simulators.append(Simulator(id: capture[2], name: capture[0], device: Device(name: capture[0], runtime: capture[1])))
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
            let booted = try bootedSimulators()
            
            guard !booted.contains(simulator) else { return }
            
            _ = try executer.execute("xcrun simctl boot '\(simulator.id)'")
            
            try waitForBoot(executer: executer, simulator: simulator)
        }
        
        func fetchSimulatorSettings() throws -> Simulators.Settings {
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
            
            if settings?.ScreenConfigurations?.keys.count == 0 {
                try CommandLineProxy.Simulators(executer: executer).forceSettingsRewrite()
                settings = try? loadSettings()
                
                if settings?.ScreenConfigurations?.keys.count == 0 {
                    throw Error("Failed to reset simulator plist: ScreenConfigurations key missing", logger: executer.logger)
                }
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
            
            _ = try executer.execute(#"rm "\#(settingsPath)""#)
            try executer.upload(localUrl: uniqueUrl, remotePath: settingsPath)
            
            // Force reload
            _ = try executer.execute("rm -rf '\(executer.homePath)/Library/Saved Application State/com.apple.iphonesimulator.savedState'")
            _ = try executer.execute("defaults read com.apple.iphonesimulator &>/dev/null")
        }
        
        private func waitForBoot(executer: Executer, simulator: Simulator) throws {
            let logPath = "\(Path.temp.rawValue)/boot_\(simulator.id)"
            let pidPath = "\(Path.temp.rawValue)/pid_\(simulator.id)"
            let timeout = 60
            
            Thread.sleep(forTimeInterval: 1.0)
            
            // This will execute simctl spawn for at most _timeout_ seconds
            try DispatchQueue.global(qos: .userInitiated).sync {
                _ = try executer.clone().execute(#"xcrun simctl spawn '\#(simulator.id)' log stream > '\#(logPath)' & echo $! > '\#(pidPath)'; sleep \#(timeout); kill $! || true"#)
            }
            
            var didFoundBootKeyword = false
            let start = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - start < TimeInterval(timeout) {
                guard try executer.execute("cat '\(logPath)' | grep 'filecoordinationd' || true").count == 0 else {
                    didFoundBootKeyword = true
                    break
                }
                
                Thread.sleep(forTimeInterval: 1.0)
            }
            
            if !didFoundBootKeyword {
                print("⚠️  did not find boot keywork in time")
            }
            
            _ = try executer.execute("kill -SIGINT $(cat \(pidPath)) || true")
        }
    }
}
