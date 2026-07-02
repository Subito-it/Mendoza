//
//  CommandLineSimulators+Settings.swift
//  Mendoza
//
//  Created by Tomas Camin on 31/01/2019.
//

import Foundation

extension CommandLineProxy.Simulators {
    func loadSimulatorSettings() throws -> Settings {
        let loadSettings: () throws -> Settings? = {
            let uniqueUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).plist")
            try self.executer.download(remotePath: self.settingsPath, localUrl: uniqueUrl)

            let data = try Data(contentsOf: uniqueUrl)

            return try PropertyListDecoder().decode(Settings.self, from: data)
        }

        var settings: Settings?
        if try executer.fileExists(atPath: settingsPath) {
            settings = try? loadSettings()
        }

        guard let result = settings else {
            throw Error("Failed loading simulator plist", logger: executer.logger)
        }

        return result
    }

    func storeSimulatorSettings(_ settings: Settings) throws {
        let data = try PropertyListEncoder().encode(settings)
        let uniqueUrl = Path.temp.url.appendingPathComponent("\(UUID().uuidString).plist")
        try data.write(to: uniqueUrl)

        _ = try executer.execute("rm '\(settingsPath)'")
        try executer.upload(localUrl: uniqueUrl, remotePath: settingsPath)

        // Force reload
        _ = try executer.execute("rm -rf '\(executer.homePath)/Library/Saved Application State/com.apple.iphonesimulator.savedState'")
    }

    func simulatorSettingsPath(for simulator: Simulator) -> String {
        "~/Library/Developer/CoreSimulator/Devices/\(simulator.id)/data/Library/Preferences"
    }

    func updateSimulatorDefaults(key: String, value: Bool) throws -> Bool {
        _ = try executer.execute("defaults write com.apple.iphonesimulator \(key) -bool \(value ? "true" : "false")")

        return false
    }

    func updateSimulatorDefaults(key: String, value: Int) throws -> Bool {
        _ = try executer.execute("defaults write com.apple.iphonesimulator \(key) \(value)")

        return false
    }

    func updatePlistIfNeeded(path: String, key: String, value: Bool) throws -> Bool {
        if try executer.execute("ls '\(path)' &>/dev/null && plutil -extract \(key) raw '\(path)' || true") != (value ? "true" : "false") {
            try createPlistIfNeeded(path: path)
            try createIntermediateKeysIfNeeded(path: path, key: key)
            _ = try executer.execute("plutil -replace \(key) -bool \(value ? "YES" : "NO") '\(path)'")
            return true
        }

        return false
    }

    func updatePlistIfNeeded(path: String, key: String, value: Int) throws -> Bool {
        if try executer.execute("ls '\(path)' &>/dev/null && plutil -extract \(key) raw '\(path)' || true") != value.description {
            try createPlistIfNeeded(path: path)
            try createIntermediateKeysIfNeeded(path: path, key: key)
            _ = try executer.execute("plutil -replace \(key) -integer \(value.description) '\(path)'")
            return true
        }

        return false
    }

    private func createPlistIfNeeded(path: String) throws {
        let exists = try executer.execute("ls '\(path)' &>/dev/null && echo 'yes' || echo 'no'")
        if exists == "no" {
            _ = try executer.execute("mkdir -p \"$(dirname '\(path)')\" && plutil -create xml1 '\(path)'")
        }
    }

    private func createIntermediateKeysIfNeeded(path: String, key: String) throws {
        let components = key.components(separatedBy: ".")
        guard components.count > 1 else { return }

        var currentKey = ""
        for component in components.dropLast() {
            if currentKey.isEmpty {
                currentKey = component
            } else {
                currentKey += ".\(component)"
            }
            let exists = try executer.execute("plutil -extract \(currentKey) raw '\(path)' &>/dev/null && echo 'yes' || echo 'no'")
            if exists == "no" {
                _ = try executer.execute("plutil -insert \(currentKey) -dictionary '\(path)'")
            }
        }
    }
}
