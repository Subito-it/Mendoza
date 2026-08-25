//
//  SimulatorServicesCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/08/2026.
//

import Bariloche
import Foundation

class SimulatorServicesCommand: Command {
    let name: String? = "sim_services"
    let usage: String? = "Disable (or restore) background services on all locally booted simulators, mimicking `test --disable_sim_services`"
    let help: String? = "Slim down booted simulators"

    let verboseFlag = Flag(short: nil, long: "verbose", help: "Dump debug messages")
    let resetFlag = Flag(short: nil, long: "reset", help: "Re-enable all services managed by mendoza instead of disabling")

    let services = Argument<String>(name: "services", kind: .named(short: nil, long: "disable"), optional: true, help: "Comma separated list of simulator background services to disable. Accepts groups or individual services. Requires iOS 18+ (ignored with a warning on older runtimes). \(SimulatorServiceCatalog.helpDescription)")

    func run() -> Bool {
        do {
            let desired = try resolveDesiredLabels()

            let executer = LocalExecuter()
            let proxy = CommandLineProxy.Simulators(executer: executer, verbose: verboseFlag.value)

            let simulators = try proxy.bootedSimulators()
            guard !simulators.isEmpty else {
                print("No booted simulators found")
                return true
            }

            print("Found \(simulators.count) booted simulator(s): \(simulators.map(\.name).joined(separator: ", "))")

            try apply(desired, to: simulators)
        } catch {
            print(error.localizedDescription.red)
            exit(-1)
        }

        return true
    }

    private func resolveDesiredLabels() throws -> Set<String> {
        if resetFlag.value {
            guard services.value == nil else {
                throw Error("Incompatible arguments: pass `\(services.longDescription)` or `\(resetFlag.description)`".red)
            }

            return []
        }

        let tokens = services.value?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        guard !tokens.isEmpty else {
            throw Error("Missing required arguments: `\(services.longDescription)` or `\(resetFlag.description)`".red)
        }

        return try SimulatorServiceCatalog.resolveLabels(for: tokens)
    }

    private func apply(_ desired: Set<String>, to simulators: [Simulator]) throws {
        let queue = OperationQueue()
        let lock = NSLock()
        var firstError: Swift.Error?
        var summaries = [String]()

        for simulator in simulators {
            // A dedicated executer per simulator: the proxy's executer is not thread-safe
            let simulatorProxy = CommandLineProxy.Simulators(executer: LocalExecuter(), verbose: verboseFlag.value)

            queue.addOperation {
                do {
                    let result = try simulatorProxy.applyDisabledServices(desired, on: simulator)
                    let disabled = try simulatorProxy.readDisabledServices(on: simulator).intersection(SimulatorServiceCatalog.managed).sorted()

                    let state = disabled.isEmpty ? "no managed services disabled" : "disabled: \(disabled.joined(separator: ", "))"

                    lock.lock()
                    summaries.append("\(simulator.name) — \(result.modified ? "updated" : "unchanged"), \(state)")
                    lock.unlock()
                } catch {
                    lock.lock()
                    firstError = firstError ?? error
                    lock.unlock()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        for summary in summaries.sorted() {
            print(summary)
        }

        if let firstError {
            throw firstError
        }
    }
}
