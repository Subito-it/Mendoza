//
//  ConfigurationAuthententicationUpdateCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Bariloche
import Foundation

class ConfigurationAuthententicationUpdateCommand: Command {
    let name: String? = "authentication"
    let usage: String? = "Update authentication data required by configuration file"
    let help: String? = "Update authentication information"

    let configuration = Argument<URL>(name: "configuration_file", kind: .positional, optional: false, help: "Mendoza's configuration file path", autocomplete: .files("json"))

    func run() -> Bool {
        do {
            try ConfigurationAuthenticationUpdater(configurationUrl: configuration.value!).run()
        } catch {
            print(error.localizedDescription.red.bold)
            exit(-1)
        }

        return true
    }
}
