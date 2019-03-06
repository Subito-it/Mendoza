//
//  PluginRootCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Bariloche
import Foundation

class PluginRootCommand: Command {
    let name: String? = "plugin"
    let usage: String? = "Plugins allow to customize and extend the dispatcher's functionality"
    let help: String? = "Customize and extend the dispatcher's functionality"
    let subcommands: [Command] = [PluginInitCommand()]
    
    func run() -> Bool {
        return true
    }
}
