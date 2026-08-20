//
//  PluginExecCommand.swift
//  Mendoza
//

import Bariloche
import Foundation

class PluginExecCommand: Command {
    let name: String? = "exec"
    let usage: String? = """
    Runs a plugin against a captured envelope, without a test session.
    
    Every invocation dumps its envelope as <name>.<timestamp>.json, under the test command's
    --plugin_replay_path or, failing that, the session logs folder. So a plugin that misbehaved
    during a session can be replayed offline. Piping that file into the plugin yourself runs it;
    this command additionally decodes the result into the type Mendoza expects, which is what
    catches a plugin whose output looks fine but cannot be consumed.
    """
    let help: String? = "Replay a captured envelope through a plugin and validate its output"

    let pluginName = Argument<String>(name: "name",
                                      kind: .positional,
                                      optional: false,
                                      help: "Plugin to run",
                                      autocomplete: .items(PluginType.autocompleteItems))
    let envelope = Argument<URL>(name: "path",
                                 kind: .named(short: nil, long: "envelope"),
                                 optional: false,
                                 help: "Path to a JSON envelope, e.g. /tmp/mendoza/logs/TearDownPlugin.20260820-154512.482.json",
                                 autocomplete: .files("json"))
    let pluginsPath = Argument<URL>(name: "path",
                                    kind: .named(short: nil, long: "plugins_path"),
                                    optional: true,
                                    help: "The folder containing the plugin executable. Default: current directory",
                                    autocomplete: .directories)

    func run() -> Bool {
        do {
            let type = try PluginType.make(pluginName.value!) // swiftlint:disable:this force_unwrapping
            let envelopeUrl = envelope.value! // swiftlint:disable:this force_unwrapping
            let baseUrl = pluginsPath.value ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            guard let envelopeData = try? Data(contentsOf: envelopeUrl) else {
                throw Error("Failed reading envelope at `\(envelopeUrl.path)`")
            }

            try print(type.exec(envelope: envelopeData, baseUrl: baseUrl))
        } catch {
            print(error.localizedDescription.red)
            exit(-1)
        }

        return true
    }
}
