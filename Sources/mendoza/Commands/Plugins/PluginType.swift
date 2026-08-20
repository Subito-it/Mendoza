//
//  PluginType.swift
//  Mendoza
//

import Bariloche
import Foundation

/// The six plugin types, named exactly as the executable Mendoza looks for at the plugins path.
enum PluginType: String, CaseIterable {
    case testExtraction = "TestExtractionPlugin"
    case testSorting = "TestSortingPlugin"
    case event = "EventPlugin"
    case preCompilation = "PreCompilationPlugin"
    case postCompilation = "PostCompilationPlugin"
    case tearDown = "TearDownPlugin"

    var help: String {
        switch self {
        case .testExtraction: return "Customize which test methods are distributed to testing nodes"
        case .testSorting: return "Provide execution time estimates to optimize the total session time"
        case .event: return "React to dispatching events (e.g. notifications)"
        case .preCompilation: return "Run custom code before compilation starts"
        case .postCompilation: return "Run custom code after compilation ends"
        case .tearDown: return "Run custom code at the end of the dispatch process"
        }
    }

    static var autocompleteItems: [Autocomplete.Item] {
        allCases.map { .init(value: $0.rawValue, help: $0.help) }
    }

    static func make(_ name: String) throws -> PluginType {
        guard let type = PluginType(rawValue: name) else {
            throw Error("Unknown plugin `\(name)`. Valid values: \(allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return type
    }

    /// Describes the plugin's stdin envelope and expected stdout, derived from the real Codable
    /// types so it cannot drift from the models.
    func describe() throws -> String {
        // No plugin data: the sample then shows `data` as the null it is when unset.
        let unset = Configuration.Plugins()

        switch self {
        case .testExtraction: return try Self.describe(TestExtractionPlugin(baseUrl: nil, plugin: unset))
        case .testSorting: return try Self.describe(TestSortingPlugin(baseUrl: nil, plugin: unset))
        case .event: return try Self.describe(EventPlugin(baseUrl: nil, plugin: unset))
        case .preCompilation: return try Self.describe(PreCompilationPlugin(baseUrl: nil, plugin: unset))
        case .postCompilation: return try Self.describe(PostCompilationPlugin(baseUrl: nil, plugin: unset))
        case .tearDown: return try Self.describe(TearDownPlugin(baseUrl: nil, plugin: unset))
        }
    }

    /// Replays a captured envelope through the very same code path a test session uses, so a
    /// plugin's output is validated against the type Mendoza will decode it into.
    func exec(envelope: Data, baseUrl: URL) throws -> String {
        switch self {
        case .testExtraction: return try Self.exec(TestExtractionPlugin(baseUrl: baseUrl), envelope: envelope)
        case .testSorting: return try Self.exec(TestSortingPlugin(baseUrl: baseUrl), envelope: envelope)
        case .event: return try Self.exec(EventPlugin(baseUrl: baseUrl), envelope: envelope)
        case .preCompilation: return try Self.exec(PreCompilationPlugin(baseUrl: baseUrl), envelope: envelope)
        case .postCompilation: return try Self.exec(PostCompilationPlugin(baseUrl: baseUrl), envelope: envelope)
        case .tearDown: return try Self.exec(TearDownPlugin(baseUrl: baseUrl), envelope: envelope)
        }
    }

    private static func describe<Input: DefaultInitializable, Output: DefaultInitializable>(_ plugin: Plugin<Input, Output>) throws -> String {
        let envelope = try plugin.makeEnvelope(input: Input.defaultInit(), prettyPrinted: true)

        let isVoidOutput = Output.self == PluginVoid.self

        var result = [String]()
        result += ["Reads this envelope on stdin:", ""]
        result += [String(decoding: envelope, as: UTF8.self), ""]
        result += ["Values are placeholders showing the shape, not real data. `data` is your"]
        result += ["--plugins_data string, passed verbatim and never parsed by Mendoza.", ""]

        if isVoidOutput {
            result += ["Writes nothing on stdout. Exit 0 for success, non-zero to fail the session.", ""]
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            result += ["Writes a JSON \(Output.self) on stdout:", ""]
            try result += [String(decoding: encoder.encode(Output.defaultInit()), as: UTF8.self), ""]
        }

        result += ["Install it as an executable named exactly `\(plugin.name)` (no extension, `chmod +x`)"]
        result += ["at --plugins_path. Any language works, it is run via its own shebang:", ""]
        result += ["    #!/usr/bin/env ruby",
                   "    require \"json\"",
                   "",
                   "    payload = JSON.parse($stdin.read)",
                   "    input   = payload[\"input\"]",
                   "    data    = JSON.parse(payload[\"data\"] || \"{}\")",
                   ""]
        result += isVoidOutput
            ? ["    warn \"log diagnostics to stderr\"    # stdout must stay empty"]
            : ["    warn \"log diagnostics to stderr\"    # never stdout, that is the result",
               "    puts JSON.generate(result)"]

        return result.joined(separator: "\n")
    }

    private static func exec<Input: DefaultInitializable, Output: DefaultInitializable>(_ plugin: Plugin<Input, Output>, envelope: Data) throws -> String {
        let output = try plugin.run(envelope: envelope)

        guard Output.self != PluginVoid.self else {
            return "✅ \(plugin.name) exited 0 and, as expected for this plugin type, wrote no output."
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try "✅ \(plugin.name) output decoded as \(Output.self):\n\(String(decoding: encoder.encode(output), as: UTF8.self))"
    }
}
