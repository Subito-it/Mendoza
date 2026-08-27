//
//  CommandLineSimulators+Services.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/08/2026.
//

import Foundation

extension CommandLineProxy.Simulators {
    /// Bounds the launchctl batch so a wedged call can't hang the node's boot queue
    /// indefinitely (neither LocalExecuter nor RemoteExecuter has a timeout). The spawns
    /// run sequentially within the batch, so the bound scales with the label count.
    private static let serviceSpawnTimeoutPerLabel: TimeInterval = 20
    private static let minimumServiceSpawnTimeout: TimeInterval = 120

    /// How many `simctl spawn` calls run concurrently per batch.
    private static let serviceSpawnBatchSize = 6

    /// Reads the labels launchd currently holds a `disabled` override for.
    ///
    /// - Note: There is no host-side file backing this: the simulator's launchd never
    ///   creates `/var/db/com.apple.xpc.launchd/disabled.plist` inside the device's data
    ///   directory, and writing one there before boot is silently ignored. The overrides
    ///   can only be read and written through `launchctl` on a booted device.
    func readDisabledServices(on simulator: Simulator) throws -> Set<String> {
        let output = try executer.execute("xcrun simctl spawn '\(simulator.id)' launchctl print-disabled system </dev/null 2>/dev/null")
        return Self.parseDisabledServices(output)
    }

    /// Parses `launchctl print-disabled system` output. A label is disabled when its value
    /// starts with `disabled` (recent launchd) or `true` (older builds).
    ///
    /// A label absent from the output has no override, which is not the same as being
    /// enabled: most daemons ship with `Disabled` set in their own plist, so this output
    /// says nothing about whether a service actually runs.
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
    func applyDisabledServices(_ desired: Set<String>, on simulator: Simulator) throws -> Bool {
        let numberFormatter = NumberFormatter()
        numberFormatter.decimalSeparator = "."
        let deviceVersion = numberFormatter.number(from: simulator.device.runtime)?.floatValue ?? 0.0

        guard deviceVersion >= 18.0 else {
            print("⚠️  Skipping simulator service slimming on \(simulator.name): requires iOS 18+, got \(simulator.device.runtime)")
            return false
        }

        let current = try readDisabledServices(on: simulator)
        let delta = SimulatorServiceCatalog.delta(current: current, desired: desired)

        guard !delta.isEmpty else { return false }

        try spawnLaunchctl(action: "disable", labels: delta.toDisable, on: simulator)
        try spawnLaunchctl(action: "enable", labels: delta.toEnable, on: simulator)

        // launchd accepts any label, including ones no job on this runtime declares, so
        // this snapshot only tells us the overrides were recorded — not that they matched
        // a real service.
        let confirmedDisabled = try readDisabledServices(on: simulator)

        // launchctl disable only prevents future launches, so a reboot is required to
        // actually stop the daemons already running.
        try shutdown(simulator: simulator)
        try bootSynchronously(simulator: simulator)

        let afterReboot = try readDisabledServices(on: simulator)

        // A label the runtime put back is one it insists on owning, which leaves the delta
        // permanently non-empty: every future run would pay this reboot again. The known
        // case is the Watch companion family, gated by `nanoregistrylaunchd` — disabling
        // that enabler is what makes them stick. Warn rather than throw: the whole feature
        // is an opportunistic memory saving, not something worth failing a session over.
        let reverted = confirmedDisabled.intersection(desired).subtracting(afterReboot)
        if !reverted.isEmpty {
            let message = """
            ⚠️  Simulator services were re-enabled after the reboot on \(simulator.name) (runtime \(simulator.device.runtime)): \
            \(reverted.sorted().joined(separator: ", ")). Every run will pay an extra reboot until whatever enables them is \
            disabled too — for Watch companion daemons that is com.apple.nanoregistrylaunchd (service id 'nanoregistrylaunchd').
            """
            print(message)
            executer.logger?.log(exception: message)
        }

        return true
    }

    private func spawnLaunchctl(action: String, labels: [String], on simulator: Simulator) throws {
        guard !labels.isEmpty else { return }

        // `launchctl` takes a single service-target per invocation (extra arguments are
        // silently ignored), so the labels are looped host-side to keep this to one
        // round trip: a spawn-per-label opened a fresh SSH connection each time and the
        // resulting contention on the node's single CoreSimulatorService is what pushed
        // individual calls past the timeout.
        //
        // Spawns can wedge right after boot, so the batch is bounded and runs on a cloned
        // executer, ensuring a leaked (timed-out) call never shares the proxy's
        // non-thread-safe executer with subsequent work. Individual failures are tolerated
        // — the post-reboot verification catches anything actually lost — but a timeout
        // aborts the whole apply since the device is not making progress.
        let clonedExecuter = try executer.clone()
        // Spelled out per label rather than looped over a shell variable: RemoteExecuter
        // wraps commands in `bash -c "…"`, so a `$var` would be expanded by the outer
        // shell and the inner one would receive an empty target.
        //
        // Each spawn is a fork plus an XPC round trip, so they run in bounded batches:
        // unbounded fan-out peaked at ~260 concurrent simctl processes per node, which is
        // reckless while 5-6 simulators are still booting. Backgrounded jobs are joined by
        // a bare `&` (`&;` is a shell syntax error) and each batch is closed by `wait`.
        let command = stride(from: 0, to: labels.count, by: Self.serviceSpawnBatchSize)
            .map { offset in
                labels[offset ..< min(offset + Self.serviceSpawnBatchSize, labels.count)]
                    .map { "xcrun simctl spawn '\(simulator.id)' launchctl \(action) 'system/\($0)' </dev/null &" }
                    .joined(separator: " ") + " wait"
            }
            .joined(separator: "; ")

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? clonedExecuter.execute(command)
            semaphore.signal()
        }

        let timeout = max(Self.minimumServiceSpawnTimeout, Double(labels.count) * Self.serviceSpawnTimeoutPerLabel)
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw Error("Timed out trying to \(action) \(labels.count) service(s) on \(simulator.name)", logger: executer.logger)
        }
    }
}
