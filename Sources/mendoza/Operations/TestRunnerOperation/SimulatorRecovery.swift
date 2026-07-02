//
//  SimulatorRecovery.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Handles simulator recovery operations when tests fail due to simulator issues
class SimulatorRecovery {
    private let verbose: Bool

    init(verbose: Bool) {
        self.verbose = verbose
    }

    /// Force reset a simulator by shutting it down
    /// xcodebuild will automatically boot it again when needed
    func forceReset(executer: Executer, testRunner: TestRunner) {
        guard let simulatorExecuter = try? executer.clone() else { return }

        let proxy = CommandLineProxy.Simulators(executer: simulatorExecuter, verbose: verbose)
        let simulator = Simulator(id: testRunner.id, name: "Simulator", device: Device.defaultInit())

        try? proxy.shutdown(simulator: simulator)
    }

    /// Boot a simulator back up after it was shut down for quarantine, waiting synchronously until
    /// it is ready. The simulator is never erased, so the configuration applied during setup
    /// (locale, keyboard, permissions, ...) is preserved.
    /// - Returns: true if the simulator was booted back successfully
    @discardableResult
    func boot(executer: Executer, testRunner: TestRunner) -> Bool {
        guard let simulatorExecuter = try? executer.clone() else { return false }

        let proxy = CommandLineProxy.Simulators(executer: simulatorExecuter, verbose: verbose)
        let simulator = Simulator(id: testRunner.id, name: "Simulator", device: Device.defaultInit())

        do {
            try proxy.bootSynchronously(simulator: simulator)
            return true
        } catch {
            return false
        }
    }

    /// Handle damaged build scenario
    /// - Returns: An error if the build folder was damaged and cleaned up
    func handleDamagedBuild(executer: Executer) throws {
        switch AddressType(address: executer.address) {
        case .local:
            _ = try executer.execute("rm -rf '\(Path.build.rawValue)' || true")
            throw Error("Tests failed because of damaged build folder, please try rerunning the build again")
        case .remote:
            // Remote nodes will get a fresh copy on next distribution
            break
        }
    }
}
