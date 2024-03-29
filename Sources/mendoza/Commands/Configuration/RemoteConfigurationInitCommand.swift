//
//  RemoteConfigurationInitCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/12/2018.
//

import Bariloche
import Foundation

class RemoteConfigurationInitCommand: Command {
    let name: String? = "init"
    let usage: String? = "Setup test dispatch configuration file"
    let help: String? = "Setup test dispatch configuration file"

    func run() -> Bool {
        do {
            try RemoteConfigurationInitializer().run()
        } catch {
            print(error.localizedDescription.red)
            exit(-1)
        }

        return true
    }
}
