//
//  BazelWorkspace.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/10/26.
//

import Foundation

/// Runs Bazel in a workspace. The configs are applied to every command that analyzes the build
/// graph: changing build options between invocations makes Bazel discard its analysis cache.
struct BazelWorkspace {
    let url: URL
    let executionRootUrl: URL
    let configs: [String]

    private let executer: Executer

    private static let cqueryFormat = """
    def format(target):
        out = {"label": str(target.label)}
        for key, provider in providers(target).items():
            if key.endswith("%AppleBundleInfo"):
                out["bundle"] = {
                    "bundle_id": provider.bundle_id,
                    "bundle_name": provider.bundle_name,
                    "bundle_extension": provider.bundle_extension,
                    "executable_name": provider.executable_name,
                    "archive": provider.archive.path,
                    "platform_type": provider.platform_type,
                }
            elif key == "SwiftInfo" or key.endswith("%SwiftInfo"):
                out["modules"] = [module.name for module in provider.direct_modules]
        return json.encode(out)
    """

    init(url: URL, executionRootUrl: URL, configs: [String], executer: Executer) {
        self.url = url
        self.executionRootUrl = executionRootUrl
        self.configs = configs
        self.executer = executer
    }

    /// - Parameter directoryUrl: any directory inside the workspace
    static func locate(directoryUrl: URL, configs: [String], executer: Executer) throws -> BazelWorkspace {
        let output = try run("info workspace execution_root", in: directoryUrl, executer: executer)
        let info = parseInfo(output)

        guard let workspace = info["workspace"], let executionRoot = info["execution_root"] else {
            throw Error("Failed reading the Bazel workspace from `bazel info`, got:\n\(output)")
        }

        return BazelWorkspace(url: URL(filePath: workspace), executionRootUrl: URL(filePath: executionRoot), configs: configs, executer: executer)
    }

    func with(executer: Executer) -> BazelWorkspace {
        BazelWorkspace(url: url, executionRootUrl: executionRootUrl, configs: configs, executer: executer)
    }

    func describeUITest(_ target: String) throws -> BazelUITest {
        let label = try single(Self.lines(query("'\(target)'")), describing: "target \(target)")
        // Configured, so a select() in test_host or deps yields only the branch the build uses
        let hostLabel = try single(cquery("'labels(test_host, \(label))'"), describing: "test host of \(label), expecting an ios_ui_test with a test_host")
        let libraryLabel = try single(cquery(#"'kind("swift_library", labels(deps, \#(label)) + labels(deps, labels(deps, \#(label))))'"#), describing: "swift_library dependency of \(label)")

        let formatUrl = FileManager.default.temporaryDirectory.appendingPathComponent("mendoza-\(UUID().uuidString).cquery")
        try Self.cqueryFormat.write(to: formatUrl, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: formatUrl) }

        // Reaching the library through the test target configures it for the simulator, as the build does
        let configuredLibrary = "deps(\(label), 2) intersect \(libraryLabel)"
        let expression = "\(label) + \(hostLabel) + (\(configuredLibrary))"
        let targets = try Self.parseCQuery(bazel("cquery \(configFlags) '\(expression)' --output=starlark --starlark:file='\(formatUrl.path)'"))

        guard let tests = targets[label]?.bundle, let app = targets[hostLabel]?.bundle else {
            throw Error("Failed reading the bundles of \(label) and \(hostLabel) from `bazel cquery`")
        }
        guard let moduleName = targets[libraryLabel]?.modules?.first else {
            throw Error("Failed reading the Swift module of \(libraryLabel) from `bazel cquery`")
        }

        let sourceLabels = try cquery(#"--notool_deps --noimplicit_deps 'kind("source file", deps(labels(srcs, \#(configuredLibrary))))'"#)

        return BazelUITest(workspace: self, label: label, hostLabel: hostLabel, app: app, tests: tests, moduleName: moduleName, sourceFiles: Self.swiftSourcePaths(fromLabels: sourceLabels))
    }

    func build(_ labels: [String]) throws {
        let targets = labels.map { "'\($0)'" }.joined(separator: " ")
        // Mendoza copies the products out of the execution root, so they must be downloaded even
        // when a config asks for --remote_download_minimal
        _ = try executer.execute("bazel build \(configFlags) --remote_download_toplevel \(targets) 2>&1", currentUrl: url, progress: nil, rethrow: nil)
    }

    private var configFlags: String {
        configs.map { "--config=\($0)" }.joined(separator: " ")
    }

    private func query(_ arguments: String) throws -> String {
        try bazel("query \(arguments)")
    }

    /// - Returns: the labels of the configured targets, which resolve select() as the build does
    private func cquery(_ arguments: String) throws -> [String] {
        try Self.configuredLabels(bazel("cquery \(configFlags) \(arguments)"))
    }

    private func bazel(_ arguments: String) throws -> String {
        try Self.run(arguments, in: url, executer: executer)
    }

    private func single(_ labels: [String], describing description: String) throws -> String {
        guard let label = labels.first, labels.count == 1 else {
            throw Error("Expecting a single \(description), found \(labels.count): \(labels.joined(separator: ", "))")
        }

        return label
    }
}

extension BazelWorkspace {
    struct CQueryTarget: Decodable {
        let label: String
        let bundle: BazelBundle?
        let modules: [String]?
    }

    /// Bazel reports progress on stderr, which the executer would otherwise mix into the parsed stdout.
    /// It is only surfaced when the command fails.
    private static func run(_ arguments: String, in directoryUrl: URL, executer: Executer) throws -> String {
        let stderrPath = FileManager.default.temporaryDirectory.appendingPathComponent("mendoza-bazel-\(UUID().uuidString).stderr").path
        let command = "bazel \(arguments) 2>'\(stderrPath)'; bazel_status=$?; [ $bazel_status -eq 0 ] || cat '\(stderrPath)'; rm -f '\(stderrPath)'; exit $bazel_status"

        return try executer.execute(command, currentUrl: directoryUrl, progress: nil, rethrow: nil)
    }

    static func parseInfo(_ output: String) -> [String: String] {
        var info = [String: String]()
        for line in lines(output) {
            guard let separator = line.range(of: ": ") else { continue }
            info[String(line[..<separator.lowerBound])] = String(line[separator.upperBound...])
        }

        return info
    }

    /// - Returns: the targets keyed by label, in the `//package:name` form `bazel query` prints
    static func parseCQuery(_ output: String) throws -> [String: CQueryTarget] {
        var targets = [String: CQueryTarget]()
        for line in lines(output) where line.hasPrefix("{") {
            let target = try JSONDecoder().decode(CQueryTarget.self, from: Data(line.utf8))
            targets[mainRepositoryLabel(target.label)] = target
        }

        return targets
    }

    /// `cquery` follows each label with its configuration, `(null)` for source files, and lists a
    /// target once per configuration it is reached in.
    /// - Returns: the distinct labels, in the `//package:name` form `bazel query` prints
    static func configuredLabels(_ output: String) -> [String] {
        var seen = Set<String>()
        return lines(output)
            .map { mainRepositoryLabel(String($0.prefix { $0 != " " })) }
            .filter { seen.insert($0).inserted }
    }

    static func swiftSourcePaths(fromLabels labels: [String]) -> [String] {
        labels.compactMap { label in
            let label = mainRepositoryLabel(label)
            guard label.hasPrefix("//"), label.hasSuffix(".swift") else { return nil }

            let components = label.dropFirst(2).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard components.count == 2 else { return nil }

            return components[0].isEmpty ? components[1] : "\(components[0])/\(components[1])"
        }
    }

    /// `cquery` prints main repository labels in their canonical `@@//package:name` form.
    private static func mainRepositoryLabel(_ label: String) -> String {
        for prefix in ["@@//", "@//"] where label.hasPrefix(prefix) {
            return String(label.dropFirst(prefix.count - 2))
        }

        return label
    }

    private static func lines(_ output: String) -> [String] {
        output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
