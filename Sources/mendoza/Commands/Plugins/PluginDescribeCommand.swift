//
//  PluginDescribeCommand.swift
//  Mendoza
//

import Bariloche
import Foundation

class PluginDescribeCommand: Command {
    let name: String? = "describe"
    let usage: String? = """
    Prints the stdin envelope a plugin receives and the stdout it should produce.
    
    A plugin is any executable named after the plugin type. Mendoza writes a single JSON
    envelope to its stdin and reads the result from its stdout, so plugins can be written in
    any language.
    """
    let help: String? = "Show a plugin's input envelope and expected output"

    let pluginName = Argument<String>(name: "name",
                                      kind: .positional,
                                      optional: false,
                                      help: "Plugin to describe",
                                      autocomplete: .items(PluginType.autocompleteItems))

    func run() -> Bool {
        do {
            try print(PluginType.make(pluginName.value!).describe()) // swiftlint:disable:this force_unwrapping
        } catch {
            print(error.localizedDescription.red)
            exit(-1)
        }

        return true
    }
}
