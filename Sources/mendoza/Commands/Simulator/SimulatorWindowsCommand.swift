//
//  SimulatorWindowsCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 14/08/2026.
//

import AppKit
import Bariloche
import Foundation

class SimulatorWindowsCommand: Command {
    let name: String? = "simulator_windows"
    let usage: String? = "Show every booted simulator in its own window. Needed because DeviceHub, which replaced Simulator.app in Xcode 27, never displays simulators booted via simctl. Runs until interrupted"
    let help: String? = "Show booted simulators in windows"

    let framesPerSecond = Argument<Double>(name: "fps", kind: .named(short: nil, long: "fps"), optional: true, help: "Refresh rate of the simulator windows. Default: 1")
    let scale = Argument<Double>(name: "factor", kind: .named(short: nil, long: "scale"), optional: true, help: "Downscale factor applied to the simulator screens. Default: 3")
    let developerDir = Argument<String>(name: "path", kind: .named(short: nil, long: "developer_dir"), optional: true, help: "Path to the Xcode developer directory whose SimulatorKit should be used. Default: the output of `xcode-select -p`", autocomplete: .directories)

    func run() -> Bool {
        do {
            let developerDir = try self.developerDir.value ?? LocalExecuter().execute("xcode-select -p")
            guard !developerDir.isEmpty else {
                throw Error("Failed determining the Xcode developer directory, pass `\(self.developerDir.longDescription)`".red)
            }

            let application = NSApplication.shared
            let windows = SimulatorWindows(developerDir: developerDir,
                                           framesPerSecond: max(0.1, framesPerSecond.value ?? 1),
                                           scale: max(1, CGFloat(scale.value ?? 3)))
            application.delegate = windows
            application.setActivationPolicy(.regular)
            application.run()
        } catch {
            print(error.localizedDescription.red)
            exit(-1)
        }

        return true
    }
}
