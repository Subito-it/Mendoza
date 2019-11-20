//
//  RootCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 01/01/2019.
//

import Bariloche

class RootCommand: Command {
    let usage: String? = "Parallelize Apple's UI tests over multiple physical nodes"
    let subcommands: [Command] = [TestCommand(), ConfigurationRootCommand(), PluginRootCommand(), MendozaCommand()]
    
    let versionFlag = Flag(short: "v", long: "version", help: "Show the version of the tool")
    
    func run() -> Bool {
        if versionFlag.value {
            print(Mendoza.version)
        }
        
        return true
    }
}
