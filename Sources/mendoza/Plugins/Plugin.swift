//
//  Plugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import CommonCrypto
import Foundation

class Plugin<Input: DefaultInitializable, Output: DefaultInitializable> {
    var isInstalled: Bool {
        fileManager.fileExists(atPath: baseUrl.appendingPathComponent(filename).path)
    }

    let logger: ExecuterLogger
    let plugin: (data: String?, debug: Bool)

    private let executer: LocalExecuter
    private let name: String
    private let baseUrl: URL
    private var filename: String { "\(name).swift" }
    private let fileManager = FileManager.default

    private let pluginOutputMarker = "# plugin-result"

    init(name: String, baseUrl: URL, plugin: (data: String?, debug: Bool)) {
        logger = ExecuterLogger(name: "Plugin-\(name)", address: "localhost")
        executer = LocalExecuter(logger: logger)
        self.name = name
        self.baseUrl = baseUrl
        self.plugin = plugin
    }

    func terminate() {
        executer.terminate()
    }

    func run(input: Input) throws -> Output {
        let start = CFAbsoluteTimeGetCurrent()
        defer { print("🔌 Plugin \(name) took \(CFAbsoluteTimeGetCurrent() - start)s".magenta) }

        let pluginUrl = baseUrl.appendingPathComponent(filename)
        // We add a suffix to the pluginname that is based on so that swift-sh has a consistent name for its internal cache

        let pluginContent = try String(contentsOf: pluginUrl)
        let pluginRunUrl = baseUrl.appendingPathComponent("_\(filename)_\(pluginContent.sha256())")

        if !fileManager.fileExists(atPath: pluginRunUrl.path) {
            // We should delete all plugins with different pluginContent suffixes
            // try? fileManager.removeItem(at: pluginRunUrl)
            try fileManager.copyItem(at: pluginUrl, to: pluginRunUrl)

            var runContent = try String(contentsOf: pluginRunUrl)
            runContent += runnerCode()

            try runContent.data(using: .utf8)?.write(to: pluginRunUrl)
        }

        let inputString: String
        if input is PluginVoid {
            inputString = ""
        } else {
            let inputJson = try JSONEncoder().encode(input)
            inputString = String(data: inputJson, encoding: .utf8)! // swiftlint:disable:this force_unwrapping
        }

        let escape: (String?) -> String = { input in
            input?
                .replacingOccurrences(of: "'", with: "’")
                .replacingOccurrences(of: #"\"#, with: #"\\"#)
                .replacingOccurrences(of: #"\\/"#, with: #"\/"#)
                ?? ""
        }

        let command = "chmod +x \(pluginRunUrl.path); \(pluginRunUrl.path) $'\(escape(inputString))' $'\(escape(plugin.data))'"

        if plugin.debug {
            let timestamp = Int(Date().timeIntervalSince1970)
            try command.data(using: .utf8)?.write(to: baseUrl.appendingPathComponent(filename + ".debug-\(timestamp)"))
        }

        do {
            if Output.self == PluginVoid.self && !plugin.debug {
                try executer.execute(command + " &")

                return Output.defaultInit()
            } else {
                let output = try executer.capture(command).output
                guard let result = output.components(separatedBy: pluginOutputMarker).last,
                      let resultData = result.data(using: .utf8), !resultData.isEmpty,
                      let ret = try? JSONDecoder().decode(Output.self, from: resultData)
                else {
                    throw Error("Failed running plugin `\(filename)`, got \(output)", logger: executer.logger)
                }
                if plugin.debug {
                    print("⚠️ plugin output:\n\(output)")
                }

                return ret
            }
        } catch {
            print(error)
            throw Error(error.localizedDescription)
        }
    }

    func writeTemplate() throws {
        let destinationUrl = baseUrl.appendingPathComponent(filename)
        var content = [String]()

        content += ["#!/usr/bin/swift", ""]
        content += ["import Foundation", ""]

        let dependencies: [DefaultInitializable.Type] = [Input.self, Output.self]
        let reflections = dependencies.flatMap { $0.reflections() }
        let uniqueSubject = Set(reflections.map(\.subject))
        let uniqueReflections = uniqueSubject.compactMap { uniqueSubject in reflections.first(where: { reflection in reflection.subject == uniqueSubject }) }.map(\.reflection)

        let dependenciesReflection = uniqueReflections.flatMap { $0.components(separatedBy: "\n") }
        let dependenciesReflectionComment = dependenciesReflection.map { "// \($0)" }
        content += dependenciesReflectionComment
        content += body().components(separatedBy: "\n")

        let data = content.joined(separator: "\n").data(using: .utf8)
        try data?.write(to: destinationUrl)

        try fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: destinationUrl.path)
    }

    private func body() -> String {
        let handleSignature: String
        switch (Input.self, Output.self) {
        case (is PluginVoid.Type, is PluginVoid.Type):
            handleSignature = "func handle(pluginData: String?) {"
        case (_, is PluginVoid.Type):
            handleSignature = "func handle(_ input: \(Input.self), pluginData: String?) {"
        case (is PluginVoid.Type, _):
            handleSignature = "func handle(pluginData: String?) -> \(Output.self) {"
        case (_, _):
            handleSignature = "func handle(_ input: \(Input.self), pluginData: String?) -> \(Output.self) {"
        }

        return """
        struct \(name) {
            \(handleSignature)
                // write your implementation here
            }
        }
        """
    }

    private func runnerCode() -> String {
        var result = ["\n"]

        let dependencies: [DefaultInitializable.Type] = [Input.self, Output.self]
        let reflections = dependencies.flatMap { $0.reflections() }
        let uniqueSubject = Set(reflections.map(\.subject))
        let uniqueReflections = uniqueSubject.compactMap { uniqueSubject in reflections.first(where: { reflection in reflection.subject == uniqueSubject }) }.map(\.reflection)

        let dependenciesReflection = uniqueReflections.flatMap { $0.components(separatedBy: "\n") }
        result += dependenciesReflection

        result += ["let pluginData = CommandLine.arguments[2]", ""]

        switch (Input.self, Output.self) {
        case (is PluginVoid.Type, is PluginVoid.Type):
            result += ["\(name)().handle(pluginData: pluginData)", ""]
            result += ["print(\"\(pluginOutputMarker)\")"]
            result += ["print(\"{}\")"]
        case (_, is PluginVoid.Type):
            result += ["let inputData = CommandLine.arguments[1].data(using: .utf8)!"]
            result += ["let input = try! JSONDecoder().decode(\(Input.self).self, from: inputData)", ""]

            result += ["\(name)().handle(input, pluginData: pluginData)", ""]
            result += ["print(\"\(pluginOutputMarker)\")"]
            result += ["print(\"{}\")"]
        case (is PluginVoid.Type, _):
            result += ["let result = \(name)().handle(pluginData: pluginData)", ""]
            result += ["print(\"\(pluginOutputMarker)\")"]
            result += ["print(\"{}\")"]
        case (_, _):
            result += ["let inputData = CommandLine.arguments[1].data(using: .utf8)!"]
            result += ["let input = try! JSONDecoder().decode(\(Input.self).self, from: inputData)", ""]

            result += ["let result = \(name)().handle(input, pluginData: pluginData)", ""]
            result += ["let outputData = try! JSONEncoder().encode(result)"]
            result += ["print(\"\(pluginOutputMarker)\")"]
            result += ["print(String(data: outputData, encoding: .utf8)!)"]
        }

        return result.joined(separator: "\n")
    }
}

private extension String {
    func sha256() -> String {
        let data = Data(utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
