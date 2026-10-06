//
//  RootCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 01/01/2019.
//

import Bariloche

class RootCommand: Command {
    let usage: String? = "Parallelize Apple's UI tests over multiple physical nodes"
    let subcommands: [Command] = [TestCommand(), RemoteConfigurationRootCommand(), PluginRootCommand(), SimulatorServicesCommand(), SimulatorWindowsCommand()]

    let versionFlag = Flag(short: "v", long: "version", help: "Show the version of the tool")

    func run() -> Bool {
        if versionFlag.value {
            print(Mendoza.version)
        }

        return true
    }
}

/// Root for `mendoza mendoza …`, the commands Mendoza runs on nodes. Bariloche lists every
/// subcommand in the help, so they live under their own root to stay out of `RootCommand`'s.
class InternalRootCommand: Command {
    static let commandName = "mendoza"

    let subcommands: [Command] = [MendozaCommand()]

    func run() -> Bool {
        true
    }
}
