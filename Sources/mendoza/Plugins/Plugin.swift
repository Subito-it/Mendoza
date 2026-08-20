//
//  Plugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

/// Not a static member of Plugin: generic types cannot hold static stored properties.
private let envelopeTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss.SSS"
    return formatter
}()

private struct PluginEnvelope<Input: Encodable>: Encodable {
    let input: Input
    let data: String?

    private enum CodingKeys: String, CodingKey {
        case input, data
    }

    // Explicit: the synthesized encoding uses encodeIfPresent and would drop `data` when
    // nil, but the contract is that the key is always present as string | null.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(input, forKey: .input)
        try container.encode(data, forKey: .data)
    }
}

class Plugin<Input: DefaultInitializable, Output: DefaultInitializable> {
    var isInstalled: Bool {
        installedUrl != nil
    }

    let logger: ExecuterLogger
    let plugin: Configuration.Plugins

    let name: String

    private let baseUrl: URL?
    private let fileManager = FileManager.default
    private let syncQueue: DispatchQueue
    private let stdinQueue: DispatchQueue
    private var runningProcesses = [Process]()

    private var installedUrl: URL? {
        guard let baseUrl else { return nil }

        let url = baseUrl.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }

        return url
    }

    init(name: String, baseUrl: URL?, plugin: Configuration.Plugins?) {
        self.logger = ExecuterLogger(name: "Plugin-\(name)", address: "localhost")
        self.name = name
        self.baseUrl = baseUrl
        self.plugin = plugin ?? .init()
        self.syncQueue = DispatchQueue(label: "com.subito.mendoza.plugin.\(name)")
        self.stdinQueue = DispatchQueue(label: "com.subito.mendoza.plugin.\(name).stdin")
    }

    func terminate() {
        syncQueue.sync {
            runningProcesses.forEach { $0.terminate() }
            runningProcesses.removeAll()
        }
    }

    func makeEnvelope(input: Input, prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        // Empty maps to null so `data` is either a string or absent-as-null, never "". The
        // usual `payload["data"] || "{}"` idiom needs that: an empty string is truthy in most
        // languages, so it would survive the fallback and then fail to parse as JSON.
        let data = plugin.data.isEmpty ? nil : plugin.data

        return try encoder.encode(PluginEnvelope(input: input, data: data))
    }

    func run(input: Input) throws -> Output {
        guard let executableUrl = installedUrl else {
            guard Output.self == PluginVoid.self else {
                throw Error("Plugin `\(name)` is not installed, expected an executable at `\(baseUrl?.path ?? "<unset plugins path>")/\(name)`", logger: logger)
            }
            return Output.defaultInit()
        }

        guard fileManager.isExecutableFile(atPath: executableUrl.path) else {
            throw Error("Plugin `\(name)` at `\(executableUrl.path)` is not executable, run `chmod +x '\(executableUrl.path)'`", logger: logger)
        }

        let start = CFAbsoluteTimeGetCurrent()
        defer { print("🔌 Plugin \(name) took \(CFAbsoluteTimeGetCurrent() - start)s".magenta) }

        let envelope = try makeEnvelope(input: input)
        let envelopeUrl = dumpEnvelope(envelope)
        let reproduceHint = envelopeUrl.map { "\nTo reproduce: cat '\($0.path)' | '\(executableUrl.path)'" } ?? ""

        let stderrUrl = try makeStderrUrl()
        defer { try? fileManager.removeItem(at: stderrUrl) }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = executableUrl
        process.standardInput = stdin
        process.standardOutput = stdout

        let stderrHandle = try FileHandle(forWritingTo: stderrUrl)
        process.standardError = stderrHandle

        logger.log(command: "\(executableUrl.path) < envelope (\(envelope.count) bytes)")

        do {
            try process.run()
        } catch {
            throw Error("Failed running plugin `\(name)`: \(error.localizedDescription)", logger: logger)
        }

        syncQueue.sync { runningProcesses.append(process) }
        defer { syncQueue.sync { runningProcesses.removeAll { $0 == process } } }

        // Off the calling thread on purpose: a plugin that ignores stdin, or that writes more
        // than a pipe buffer to stdout before consuming its input, would deadlock against the
        // stdout read below. Write failures are expected when a plugin exits early.
        stdinQueue.async {
            try? stdin.fileHandleForWriting.write(contentsOf: envelope)
            try? stdin.fileHandleForWriting.close()
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        try? stderrHandle.close()
        let standardError = (try? String(contentsOf: stderrUrl)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let output = String(decoding: outputData, as: UTF8.self)

        logger.log(output: [standardError.isEmpty ? nil : "stderr:\n\(standardError)",
                            output.isEmpty ? nil : "stdout:\n\(output)"].compactMap { $0 }.joined(separator: "\n\n"),
                   statusCode: process.terminationStatus)

        guard process.terminationStatus == 0 else {
            let details = standardError.isEmpty ? "" : "\n\(standardError)"
            throw Error("Plugin `\(name)` failed with status code \(process.terminationStatus)\(details)\(reproduceHint)", logger: logger)
        }

        guard Output.self != PluginVoid.self else { return Output.defaultInit() }

        guard !outputData.isEmpty else {
            throw Error("Plugin `\(name)` wrote nothing to stdout, expected a JSON \(Output.self)\(reproduceHint)", logger: logger)
        }

        do {
            return try JSONDecoder().decode(Output.self, from: outputData)
        } catch {
            throw Error("Plugin `\(name)` wrote stdout that cannot be decoded as \(Output.self): \(error.localizedDescription)\nGot: \(output)\(reproduceHint)", logger: logger)
        }
    }

    private func makeStderrUrl() throws -> URL {
        let url = Path.temp.url.appendingPathComponent("\(name)-\(UUID().uuidString).stderr")
        try? fileManager.createDirectory(at: Path.temp.url, withIntermediateDirectories: true)
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw Error("Failed creating a temporary file to capture `\(name)`'s stderr", logger: logger)
        }
        return url
    }

    /// Always dumps, so that the input of a failing plugin is on disk before anyone knows they
    /// want it. Returns nil rather than throwing: losing the dump must not fail the run.
    private func dumpEnvelope(_ envelope: Data) -> URL? {
        let directory = plugin.replayPath.map { URL(fileURLWithPath: $0.pathExpandingTilde()) } ?? Path.logs.url
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Millisecond precision: EventPlugin can fire twice within the same second, and one
        // invocation overwriting another's envelope would be worse than not keeping it.
        let url = directory.appendingPathComponent("\(name).\(envelopeTimestampFormatter.string(from: Date())).json")

        guard (try? envelope.write(to: url, options: .atomic)) != nil else { return nil }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        return url
    }
}
