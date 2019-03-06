//
//  ConfigurationInitCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/12/2018.
//

import Foundation
import Bariloche

class ConfigurationInitCommand: Command {
    let name: String? = "init"
    let usage: String? = "Setup test dispatch configuration file"
    let help: String? = "Setup test dispatch configuration file"
    
    func run() -> Bool {
        do {
            try ConfigurationInitializer().run()
        } catch let error {
            print(error.localizedDescription.red)
            exit(-1)
        }
        
        return true
    }
}
