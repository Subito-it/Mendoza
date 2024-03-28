//
//  ConfigurationRootCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Bariloche
import Foundation

class RemoteConfigurationRootCommand: Command {
    let name: String? = "configuration"
    let usage: String? = "Initialize and update dispatcher configurations"
    let help: String? = "Configure dispatcher"
    let subcommands: [Command] = [RemoteConfigurationInitCommand(), RemoteConfigurationAuthententicationUpdateCommand()]

    func run() -> Bool {
        true
    }
}
