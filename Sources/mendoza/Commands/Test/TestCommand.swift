//
//  TestCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/12/2018.
//

import Bariloche
import Foundation

class TestCommand: Command {
    let name: String? = "test"
    let usage: String? = "Dispatch UI tests as specified in the `configuration_file`"
    let help: String? = "Dispatch UI tests"

    let pluginReplayPath = Argument<URL>(name: "path", kind: .named(short: nil, long: "plugin_replay_path"), optional: true, help: "Folder where every plugin invocation's stdin envelope is written, as `<PluginName>.<timestamp>.json`, so a failing plugin can be re-run against the exact input it received. Default: the session logs folder, which is wiped when the next session starts", autocomplete: .directories)
    let verboseFlag = Flag(short: nil, long: "verbose", help: "Dump debug messages")

    let remoteNodesConfigurationPath = Argument<URL>(name: "path", kind: .named(short: nil, long: "remote_nodes_configuration"), optional: true, help: "Path to remote configuration file containing the list of remote nodes to use and destination path")
    let localDestinationPath = Argument<URL>(name: "path", kind: .named(short: nil, long: "local_destination_path"), optional: true, help: "Specify location to store tests results that will be executed locally")
    let localTestsRunners = Argument<Int>(name: "count", kind: .named(short: nil, long: "local_tests_runners"), optional: true, help: "Specify the number of concurrent tests to execute. Default: automatically determine based on available cores")
    let includePattern = Argument<String>(name: "files", kind: .named(short: nil, long: "include_files"), optional: true, help: "Specify from which files UI tests should be extracted. Accepts wildcards and comma separated values. e.g SBTA*.swift,SBTF*.swift. Default: '*.swift'", autocomplete: .files("swift"))
    let excludePattern = Argument<String>(name: "files", kind: .named(short: nil, long: "exclude_files"), optional: true, help: "Specify which files should be skipped when extracting UI tests. Accepts wildcards and comma separated values. e.g SBTA*.swift,SBTF*.swift. Default: ''", autocomplete: .files("swift"))
    let deviceName = Argument<String>(name: "name", kind: .named(short: nil, long: "device_name"), optional: true, help: "Device name to use to run tests. e.g. 'iPhone 8'")
    let deviceRuntime = Argument<String>(name: "version", kind: .named(short: nil, long: "device_runtime"), optional: true, help: "Device runtime to use to run tests. e.g. '13.0'")
    let deviceLanguage = Argument<String>(name: "language", kind: .named(short: nil, long: "device_language"), optional: true, help: "Device language. e.g. 'en-EN'")
    let deviceLocale = Argument<String>(name: "locale", kind: .named(short: nil, long: "device_locale"), optional: true, help: "Device locale. e.g. 'en_US'")
    let autodeleteSlowDevices = Flag(short: nil, long: "delete_slow_devices", help: "Automatically delete devices that took longer than expected to start dispatching tests. When such a case is detected on a node all its devices will be deleted which is the only workaround to avoid this delay to happen in future test dispatches")
    let alwaysRebootSimulators = Flag(short: nil, long: "reboot_simulators", help: "Always reboot simulators before launching tests")
    let maximumStdOutIdleTime = Argument<Int>(name: "seconds", kind: .named(short: nil, long: "stdout_timeout"), optional: true, help: "Maximum allowed idle time (in seconds) in standard output before test is automatically terminated")
    let maximumTestExecutionTime = Argument<Int>(name: "seconds", kind: .named(short: nil, long: "max_execution_time"), optional: true, help: "Maximum execution time (in seconds) before test fails with a timeout error")
    let pluginCustom = Argument<String>(name: "data", kind: .named(short: nil, long: "plugin_data"), optional: true, help: "A custom string that can be used to inject data to plugins")
    let failingTestsRetryCount = Argument<Int>(name: "count", kind: .named(short: nil, long: "failure_retry"), optional: true, help: "Number of times a failing tests should be repeated")
    let codeCoveragePathEquivalence = Argument<String>(name: "path", kind: .named(short: nil, long: "llvm_cov_equivalence_path"), optional: true, help: "Path equivalence path passed to 'llvm-cov show' when extracting code coverage (<from1>,<to1>,<from2>,<to2>...)")
    let extractIndividualTestCoverage = Flag(short: nil, long: "individual_test_coverage", help: "Extract individual test coverage .jsons to results/individual_coverage")
    let extractTestCoveredFiles = Flag(short: nil, long: "test_covered_files", help: "Extract list of files covered by each test to results/test_covered_files")
    let xcodeBuildNumber = Argument<String>(name: "number", kind: .named(short: nil, long: "xcode_buildnumber"), optional: true, help: "Build number of the Xcode version to use (e.g. 12E507)")
    let skipResultMerge = Flag(short: nil, long: "skip_result_merge", help: "Skip xcresult merge (keep one xcresult per test in the result folder)")
    let clearDerivedDataOnCompilationFailure = Flag(short: nil, long: "clear_derived_data_on_failure", help: "[xcodebuild] On compilation failure derived data will be cleared and compilation will be retried once. Ignored with --bazel_target")
    let xcresultBlobThresholdKB = Argument<Int>(name: "size", kind: .named(short: nil, long: "xcresult_blob_threshold_kb"), optional: true, help: "Delete data blobs larger than the specified threshold")
    let excludeNodes = Argument<String>(name: "nodes", kind: .named(short: nil, long: "exclude_nodes"), optional: true, help: "Specify which nodes (by name or address) specified in the configuration should be excluded from the dispatch. Accepts comma separated values. Default: ''")
    let disabledSimulatorServices = Argument<String>(name: "services", kind: .named(short: nil, long: "disable_sim_services"), optional: true, help: "Comma separated list of simulator background services to disable to slim down memory usage. Accepts groups or individual services. Requires iOS 18+ (ignored with a warning on older runtimes). \(SimulatorServiceCatalog.helpDescription)")
    let keepBuildFolderOnFailure = Flag(short: nil, long: "keep_build_folder_on_failure", help: "Keep build folder on failure")
    let collectTestDiagnosticsOnFailure = Flag(short: nil, long: "collect_test_diagnostics_on_failure", help: "Collect verbose xcodebuild diagnostics (sysdiagnose, log archives) when a test fails. ⚠️ Significant performance regression: xcodebuild runs `simctl diagnose` with a 600s timeout after the test verdict is known, writing ~280MB into the .xcresult while the simulator stays out of rotation. Default: diagnostics collection is disabled")

    let projectPath = Argument<URL>(name: "path", kind: .named(short: nil, long: "project"), optional: true, help: "The path to the .xcworkspace or .xcodeproj to build. Required unless building with --bazel_target")
    let scheme = Argument<String>(name: "name", kind: .named(short: nil, long: "scheme"), optional: true, help: "The scheme to build. Required unless building with --bazel_target")
    let bazelTarget = Argument<String>(name: "label", kind: .named(short: nil, long: "bazel_target"), optional: true, help: "Build with Bazel instead of xcodebuild: the ios_ui_test target to run, e.g. //App:AppUITests. Run mendoza from inside the Bazel workspace. Replaces --project and --scheme")
    let bazelConfigs = Argument<String>(name: "configs", kind: .named(short: nil, long: "bazel_config"), optional: true, help: "Comma separated Bazel configs (as in --config) applied to the build, e.g. ci,remote_cache. Pass the configs your other builds use to reuse their cache. Default: ''")
    let buildConfiguration = Argument<String>(name: "name", kind: .named(short: nil, long: "build_configuration"), optional: true, help: "Build configuration. Default: Debug")
    let buildSettings = Argument<String>(name: "settings", kind: .named(short: nil, long: "build_settings"), optional: true, help: "Additional build settings passed to xcodebuild, e.g. \"SWIFT_COMPILATION_MODE=wholemodule COMPILATION_CACHE_CAS_PATH=/path/to/cas\". These outrank the project's own settings, so only pass what you intend to override. Default: ''")
    let pluginsBasePath = Argument<URL>(name: "path", kind: .named(short: nil, long: "plugins_path"), optional: true, help: "The path to the folder containing Mendoza's plugins")

    func run() -> Bool {
        do {
            let (configuration, bazelTest) = try makeConfiguration()

            let pluginUrl = pluginsBasePath.value ?? remoteConfigurationUrl()

            let projectUrl = URL(filePath: configuration.building.projectPath)
            FileManager.default.changeCurrentDirectoryPath(bazelTest == nil ? projectUrl.deletingLastPathComponent().path : projectUrl.path)

            let test = try Test(configuration: configuration, pluginUrl: pluginUrl, bazelTest: bazelTest)

            test.didFail = { [weak self] in self?.handleError($0) }
            try test.run()
        } catch {
            if keepBuildFolderOnFailure.value {
                let executer = LocalExecuter()
                let uuid = UUID().uuidString
                let destinationPath = "\(Path.base.rawValue)-\(uuid)"
                _ = try? executer.execute("mv '\(Path.base.rawValue)' '\(destinationPath)'")
                print("Keeping logs at \(destinationPath)")
            }
            handleError(error)
        }

        return true
    }

    private func makeConfiguration() throws -> (Configuration, BazelUITest?) {
        if remoteNodesConfigurationPath.value?.path.isEmpty == true, localDestinationPath.value?.path.isEmpty == true {
            throw Error("Missing required arguments: `\(remoteNodesConfigurationPath.longDescription)=\(remoteNodesConfigurationPath.name)` or `\(localDestinationPath.longDescription)=\(localDestinationPath.name)`".red)
        } else if remoteNodesConfigurationPath.value?.path.isEmpty == localDestinationPath.value?.path.isEmpty {
            throw Error("Incompatible arguments: pass `\(remoteNodesConfigurationPath.longDescription)=\(remoteNodesConfigurationPath.name)` or `\(localDestinationPath.longDescription)=\(localDestinationPath.name)`".red)
        }

        let projectUrl: URL
        let scheme: String
        let sdk: XcodeProject.SDK
        let bundleIdentifiers: (build: String, test: String)
        let bazel: Configuration.Building.Bazel?
        let bazelTest: BazelUITest?

        if let bazelTargetValue = bazelTarget.value {
            let xcodeOnlyArguments = [projectPath.value == nil ? nil : projectPath.longDescription,
                                      self.scheme.value == nil ? nil : self.scheme.longDescription,
                                      buildConfiguration.value == nil ? nil : buildConfiguration.longDescription,
                                      buildSettings.value == nil ? nil : buildSettings.longDescription].compactMap { $0 }
            guard xcodeOnlyArguments.isEmpty else {
                throw Error("Incompatible arguments: \(xcodeOnlyArguments.joined(separator: ", ")) only apply to xcodebuild builds, configure the Bazel build with `\(bazelConfigs.longDescription)`".red)
            }

            let configs = try parseBazelConfigs()
            guard !bazelTargetValue.contains("'") else { throw Error("Invalid Bazel target \(bazelTargetValue)".red) }

            let workspace = try BazelWorkspace.locate(directoryUrl: URL(filePath: FileManager.default.currentDirectoryPath), configs: configs, executer: LocalExecuter())
            let test = try workspace.describeUITest(bazelTargetValue)
            guard test.tests.platformType == "ios" else {
                throw Error("Unsupported Bazel target \(test.label): only iOS UI tests are supported, got platform \(test.tests.platformType)".red)
            }

            projectUrl = workspace.url
            scheme = test.moduleName
            sdk = .ios
            bundleIdentifiers = (build: test.app.bundleIdentifier, test: test.tests.bundleIdentifier)
            bazel = .init(target: test.label, configs: configs)
            bazelTest = test
        } else {
            guard let projectPathValue = projectPath.value, let schemeValue = self.scheme.value else {
                throw Error("Missing required arguments `\(projectPath.longDescription)=\(projectPath.name)` and `\(self.scheme.longDescription)=\(self.scheme.name)`, or `\(bazelTarget.longDescription)=\(bazelTarget.name)` to build with Bazel".red)
            }
            guard bazelConfigs.value == nil else {
                throw Error("Incompatible arguments: `\(bazelConfigs.longDescription)` requires `\(bazelTarget.longDescription)`".red)
            }

            let project = try XcodeProject(url: projectPathValue)

            projectUrl = projectPathValue
            scheme = schemeValue
            sdk = deviceName.value != nil ? .ios : try project.getBuildSDK(scheme: schemeValue)
            bundleIdentifiers = try project.getTargetsBundleIdentifiers(scheme: schemeValue)
            bazel = nil
            bazelTest = nil
        }

        let device: Device?
        switch sdk {
        case .ios:
            if deviceName.value?.isEmpty == true, deviceRuntime.value?.isEmpty == true {
                throw Error("Missing required arguments `\(deviceName.longDescription)=\(deviceName.name)`, `\(deviceRuntime.longDescription)=\(deviceRuntime.name)`".red)
            } else if deviceName.value?.isEmpty == true {
                throw Error("Missing required arguments `\(deviceName.longDescription)=\(deviceName.name)`".red)
            } else if deviceRuntime.value?.isEmpty == true {
                throw Error("Missing required arguments `\(deviceRuntime.longDescription)=\(deviceRuntime.name)`".red)
            }

            device = Device(name: deviceName.value!, runtime: deviceRuntime.value!, language: deviceLanguage.value, locale: deviceLocale.value)
        case .macos:
            device = nil
        }

        let buildConfiguration = self.buildConfiguration.value ?? "Debug"
        let xcodeBuildNumber = self.xcodeBuildNumber.value

        let filePatterns = FilePatterns(commaSeparatedIncludePattern: includePattern.value, commaSeparatedExcludePattern: excludePattern.value)

        let settings = Configuration.Building.Settings(buildSettings: buildSettings.value ?? "")

        let building = Configuration.Building(projectPath: projectUrl.path, bazel: bazel, buildBundleIdentifier: bundleIdentifiers.build, testBundleIdentifier: bundleIdentifiers.test, scheme: scheme, buildConfiguration: buildConfiguration, sdk: sdk.rawValue, settings: settings, filePatterns: filePatterns, xcodeBuildNumber: xcodeBuildNumber)

        if let codeCoveragePathEquivalenceValue = codeCoveragePathEquivalence.value {
            if codeCoveragePathEquivalenceValue.components(separatedBy: ",").count % 2 != 0 {
                throw Error("Invalid format for \(codeCoveragePathEquivalence.longDescription) parameter, expecting \(codeCoveragePathEquivalence.longDescription)=<from>,<to> with even number of pairs".red)
            }
        }

        var clearDerivedData = clearDerivedDataOnCompilationFailure.value
        if clearDerivedData, bazel != nil {
            print("⚠️  \(clearDerivedDataOnCompilationFailure) is ignored when building with Bazel, which keeps its build state in its output base".yellow)
            clearDerivedData = false
        }

        let disabledServices = disabledSimulatorServices.value?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        _ = try SimulatorServiceCatalog.resolveLabels(for: disabledServices) // validate tokens up front

        let testing = Configuration.Testing(maximumStdOutIdleTime: maximumStdOutIdleTime.value,
                                            maximumTestExecutionTime: maximumTestExecutionTime.value,
                                            failingTestsRetryCount: failingTestsRetryCount.value,
                                            xcresultBlobThresholdKB: xcresultBlobThresholdKB.value,
                                            alwaysRebootSimulators: alwaysRebootSimulators.value,
                                            autodeleteSlowDevices: autodeleteSlowDevices.value,
                                            codeCoveragePathEquivalence: codeCoveragePathEquivalence.value,
                                            extractIndividualTestCoverage: extractIndividualTestCoverage.value,
                                            extractTestCoveredFiles: extractTestCoveredFiles.value,
                                            clearDerivedDataOnCompilationFailure: clearDerivedData,
                                            skipResultMerge: skipResultMerge.value,
                                            disabledSimulatorServices: disabledServices,
                                            collectTestDiagnosticsOnFailure: collectTestDiagnosticsOnFailure.value)

        let plugins = Configuration.Plugins(data: pluginCustom.value ?? "", replayPath: pluginReplayPath.value?.path)

        let resultDestination: ConfigurationResultDestination
        var nodes: [Node]

        if let destinationPath = localDestinationPath.value?.path() {
            let node: Node
            if let localConcurrentTestRunners = localTestsRunners.value {
                node = .localhost(concurrentTestRunners: .manual(count: UInt(localConcurrentTestRunners)))
            } else {
                node = .localhost(concurrentTestRunners: .autodetect)
            }
            resultDestination = .init(node: node, path: destinationPath)
            nodes = [node]
        } else if let remotePath = remoteNodesConfigurationPath.value {
            let remoteConfiguration = try JSONDecoder().decode(RemoteConfiguration.self, from: Data(contentsOf: remotePath))
            nodes = remoteConfiguration.nodes

            if let excludedNodes = excludeNodes.value?.components(separatedBy: ",") {
                nodes = nodes.filter { node in !excludedNodes.contains(node.address) && !excludedNodes.contains(node.name) }
                if nodes.isEmpty {
                    throw Error("No dispatch nodes left, double check that the `\(excludeNodes.longDescription)` parameter does not contain all nodes specified in the configuration files")
                }
            }

            resultDestination = remoteConfiguration.resultDestination
        } else {
            throw Error("Missing required arguments `\(deviceName.longDescription)=\(deviceName.name)`, `\(deviceRuntime.longDescription)=\(deviceRuntime.name)`".red)
        }

        return (Configuration(building: building, testing: testing, device: device, plugins: plugins, resultDestination: resultDestination, nodes: nodes, verbose: verboseFlag.value), bazelTest)
    }

    private func parseBazelConfigs() throws -> [String] {
        let configs = bazelConfigs.value?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        let invalidConfigs = configs.filter { $0.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) == nil }
        guard invalidConfigs.isEmpty else {
            throw Error("Invalid \(bazelConfigs.longDescription) values: \(invalidConfigs.joined(separator: ", "))".red)
        }

        return configs
    }

    private func remoteConfigurationUrl() -> URL? {
        guard let remoteConfigurationUrl = remoteNodesConfigurationPath.value?.deletingLastPathComponent() else {
            return nil
        }

        if remoteConfigurationUrl.path().starts(with: "/") == true {
            return remoteConfigurationUrl
        } else {
            return URL(filePath: FileManager.default.currentDirectoryPath).appending(path: remoteConfigurationUrl.path())
        }
    }

    private func handleError(_ error: Swift.Error) {
        print(error.localizedDescription)

        if !(error is Error) {
            print("\n\(String(describing: error))")
        }

        exit(-1)
    }
}
