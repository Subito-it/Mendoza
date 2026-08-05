//
//  CommandLineSimulators+Services.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/08/2026.
//

import Foundation

extension CommandLineProxy.Simulators {
    /// Bounds a single launchctl spawn so a wedged call can't hang the node's boot
    /// queue indefinitely (neither LocalExecuter nor RemoteExecuter has a timeout).
    private static let serviceSpawnTimeout: TimeInterval = 120

    func readDisabledServices(on simulator: Simulator) throws -> Set<String> {
        let output = try executer.execute("xcrun simctl spawn '\(simulator.id)' launchctl print-disabled system 2>/dev/null")
        return Self.parseDisabledServices(output)
    }

    /// Parses `launchctl print-disabled system` output. A label is disabled when its
    /// value starts with `disabled` (recent launchd) or `true` (older builds); a label
    /// absent from the output is enabled.
    static func parseDisabledServices(_ output: String) -> Set<String> {
        var result = Set<String>()

        for line in output.components(separatedBy: "\n") {
            guard let open = line.firstIndex(of: "\"") else { continue }
            let afterOpen = line.index(after: open)
            guard let close = line[afterOpen...].firstIndex(of: "\"") else { continue }
            guard let arrow = line[close...].range(of: "=>") else { continue }

            let value = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("disabled") || value.hasPrefix("true") else { continue }

            result.insert(String(line[afterOpen ..< close]))
        }

        return result
    }

    /// Converges the simulator's disabled launchd services to `desired`, rebooting only
    /// if something changed. Returns whether the device was modified.
    ///
    /// - Note: The overrides only persist across reboots on iOS 18+, so the feature is
    ///   gated on the runtime version and verified after the reboot.
    @discardableResult
    func applyDisabledServices(_ desired: Set<String>, on simulator: Simulator) throws -> Bool {
        let numberFormatter = NumberFormatter()
        numberFormatter.decimalSeparator = "."
        let deviceVersion = numberFormatter.number(from: simulator.device.runtime)?.floatValue ?? 0.0

        guard deviceVersion >= 18.0 else {
            print("⚠️  Skipping simulator service slimming on \(simulator.name): requires iOS 18+, got \(simulator.device.runtime)")
            return false
        }

        let current = try readDisabledServices(on: simulator)
        let delta = serviceDelta(current: current, desired: desired)

        guard !delta.toDisable.isEmpty || !delta.toEnable.isEmpty else {
            return false
        }

        for label in delta.toDisable {
            try spawnLaunchctl(action: "disable", label: label, on: simulator)
        }
        for label in delta.toEnable {
            try spawnLaunchctl(action: "enable", label: label, on: simulator)
        }

        // launchctl disable only prevents future launches, so a reboot is required to
        // actually stop the daemons already running.
        try shutdown(simulator: simulator)
        try bootSynchronously(simulator: simulator)

        let afterReboot = try readDisabledServices(on: simulator)
        let residual = serviceDelta(current: afterReboot, desired: desired)
        if !residual.toDisable.isEmpty {
            throw Error("Simulator service overrides were not persisted on \(simulator.name) (runtime \(simulator.device.runtime)). Lost: \(residual.toDisable.joined(separator: ", "))", logger: executer.logger)
        }

        return true
    }

    private func spawnLaunchctl(action: String, label: String, on simulator: Simulator) throws {
        // A single spawn can wedge right after boot; bound it so it can't hang the node
        // forever. We run on a cloned executer so a leaked (timed-out) call never shares
        // the proxy's non-thread-safe executer with subsequent work. Individual failures
        // are tolerated — the post-reboot verification catches anything actually lost —
        // but a timeout aborts the whole apply since the device is not making progress.
        let clonedExecuter = try executer.clone()
        let command = "xcrun simctl spawn '\(simulator.id)' launchctl \(action) system/\(label)"

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? clonedExecuter.execute(command)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + Self.serviceSpawnTimeout) == .timedOut {
            throw Error("Timed out trying to \(action) \(label) on \(simulator.name)", logger: executer.logger)
        }
    }
}
