//
//  PluginInitCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Bariloche
import Foundation

class PluginInitCommand: Command {
    let name: String? = "init"
    let usage: String? = """
Plugins allow to customize and extend the functionality of the dispatcher.

Valid values for the `name` parameter are: `extract`, `sorting`, `event`, `precompilation`, `postcompilation`.
- `extract`: allows to specify the test methods that should be performed in every test file
- `sorting`: allows to sort tests in order to improve total execution time
- `event`: plugin to perform actions (e.g. notifications) based on dispatching events
- `precompilation`: plugin to perform actions before compilation starts
- `postcompilation`: plugin to perform actions after compilation completes
- `teardown`: plugin to perform actions at the end of the dispatch process
"""
    let help: String? = "Initialize plugins"
    
    let configuration = Argument<URL>(name: "configuration_file", kind: .positional, optional: false, help: "Mendoza's configuration file path", autocomplete: .files("json"))
    let pluginName = Argument<String>(name: "name",
                                      kind: .positional,
                                      optional: false,
                                      help: "Plugin to initialize",
                                      autocomplete: .items([.init(value: "extract", help: "Customize test method extraction"),
                                                            .init(value: "sorting", help: "Sort tests to improve execution time"),
                                                            .init(value: "event", help: "Event based plugin"),
                                                            .init(value: "precompilation", help: "Run custom code before compilation"),
                                                            .init(value: "postcompilation", help: "Run custom code after compilation"),
                                                            .init(value: "teardown", help: "Run custom code at the end of execution")]))
    
    func run() -> Bool {
        do {
            let initer = PluginInit(configurationUrl: configuration.value!, name: pluginName.value!)
            try initer.run()
        } catch let error {
            print(error.localizedDescription.red)
            exit(-1)
        }
        
        return true
    }
}
