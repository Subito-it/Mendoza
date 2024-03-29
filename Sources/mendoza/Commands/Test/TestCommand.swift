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

    let debugPluginsFlag = Flag(short: nil, long: "plugin_debug", help: "Dump plugin invocation commands")
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
    let maximumStdOutIdleTime = Argument<Int>(name: "seconds", kind: .named(short: nil, long: "stdout_timeout"), optional: true, help: "Maximum allowed idle time (in seconds) in standard output before test is automatically terminated")
    let maximumTestExecutionTime = Argument<Int>(name: "seconds", kind: .named(short: nil, long: "max_execution_time"), optional: true, help: "Maximum execution time (in seconds) before test fails with a timeout error")
    let pluginCustom = Argument<String>(name: "data", kind: .named(short: nil, long: "plugin_data"), optional: true, help: "A custom string that can be used to inject data to plugins")
    let failingTestsRetryCount = Argument<Int>(name: "count", kind: .named(short: nil, long: "failure_retry"), optional: true, help: "Number of times a failing tests should be repeated")
    let codeCoveragePathEquivalence = Argument<String>(name: "path", kind: .named(short: nil, long: "llvm_cov_equivalence_path"), optional: true, help: "Path equivalence path passed to 'llvm-cov show' when extracting code coverage (<from>,<to>)")
    let xcodeBuildNumber = Argument<String>(name: "number", kind: .named(short: nil, long: "xcode_buildnumber"), optional: true, help: "Build number of the Xcode version to use (e.g. 12E507)")
    let skipResultMerge = Flag(short: nil, long: "skip_result_merge", help: "Skip xcresult merge (keep one xcresult per test in the result folder)")
    let clearDerivedDataOnCompilationFailure = Flag(short: nil, long: "clear_derived_data_on_failure", help: "On compilation failure derived data will be cleared and compilation will be retried once")
    let xcresultBlobThresholdKB = Argument<Int>(name: "size", kind: .named(short: nil, long: "xcresult_blob_threshold_kb"), optional: true, help: "Delete data blobs larger than the specified threshold")
    let excludeNodes = Argument<String>(name: "nodes", kind: .named(short: nil, long: "exclude_nodes"), optional: true, help: "Specify which nodes (by name or address) specified in the configuration should be excluded from the dispatch. Accepts comma separated values. Default: ''")
    let killSimulatorProcesses = Flag(short: nil, long: "kill_sim_procs", help: "Automatically kill Simulator's CPU intensive processes, see https://github.com/biscuitehh/yeetd")

    let projectPath = Argument<URL>(name: "path", kind: .named(short: nil, long: "project"), optional: false, help: "The path to the .xcworkspace or .xcodeproj to build")
    let scheme = Argument<String>(name: "name", kind: .named(short: nil, long: "scheme"), optional: false, help: "The scheme to build")
    let buildConfiguration = Argument<String>(name: "name", kind: .named(short: nil, long: "build_configuration"), optional: true, help: "Build configuration. Default: Debug")
    let pluginsBasePath = Argument<URL>(name: "path", kind: .named(short: nil, long: "plugins_path"), optional: true, help: "The path to the folder containing Mendoza's plugins")

    func run() -> Bool {
        do {
            let configuration = try makeConfiguration()

            let pluginUrl = pluginsBasePath.value ?? remoteConfigurationUrl()

            FileManager.default.changeCurrentDirectoryPath(URL(filePath: configuration.building.projectPath).deletingLastPathComponent().path)

            let test = try Test(configuration: configuration, pluginUrl: pluginUrl)

            test.didFail = { [weak self] in self?.handleError($0) }
            try test.run()
        } catch {
            handleError(error)
        }

        return true
    }

    private func makeConfiguration() throws -> ModernConfiguration {
        if remoteNodesConfigurationPath.value?.path.isEmpty == true, localDestinationPath.value?.path.isEmpty == true {
            throw Error("Missing required arguments: `\(remoteNodesConfigurationPath.longDescription)=\(remoteNodesConfigurationPath.name)` or `\(localDestinationPath.longDescription)=\(localDestinationPath.name)`".red)
        } else if remoteNodesConfigurationPath.value?.path.isEmpty == localDestinationPath.value?.path.isEmpty {
            throw Error("Incompatible arguments: pass `\(remoteNodesConfigurationPath.longDescription)=\(remoteNodesConfigurationPath.name)` or `\(localDestinationPath.longDescription)=\(localDestinationPath.name)`".red)
        }

        let projectUrl = projectPath.value!
        let project = try XcodeProject(url: projectUrl)
        let scheme = self.scheme.value!

        let sdk: XcodeProject.SDK
        if deviceName.value != nil {
            sdk = .ios
        } else {
            sdk = try project.getBuildSDK(scheme: scheme)
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

        let bundleIdentifiers = try project.getTargetsBundleIdentifiers(scheme: scheme)
        let buildConfiguration = self.buildConfiguration.value ?? "Debug"
        let xcodeBuildNumber = self.xcodeBuildNumber.value

        let filePatterns = FilePatterns(commaSeparatedIncludePattern: includePattern.value, commaSeparatedExcludePattern: excludePattern.value)

        let building = ModernConfiguration.Building(projectPath: projectUrl.path, buildBundleIdentifier: bundleIdentifiers.build, testBundleIdentifier: bundleIdentifiers.test, scheme: scheme, buildConfiguration: buildConfiguration, sdk: sdk.rawValue, filePatterns: filePatterns, xcodeBuildNumber: xcodeBuildNumber)

        if let codeCoveragePathEquivalenceValue = codeCoveragePathEquivalence.value {
            if codeCoveragePathEquivalenceValue.components(separatedBy: ",").count % 2 != 0 {
                throw Error("Invalid format for \(codeCoveragePathEquivalence.longDescription) parameter, expecting \(codeCoveragePathEquivalence.longDescription)=<from>,<to> with even number of pairs".red)
            }
        }

        let testing = ModernConfiguration.Testing(maximumStdOutIdleTime: maximumStdOutIdleTime.value,
                                                  maximumTestExecutionTime: maximumTestExecutionTime.value,
                                                  failingTestsRetryCount: failingTestsRetryCount.value,
                                                  xcresultBlobThresholdKB: xcresultBlobThresholdKB.value,
                                                  killSimulatorProcesses: killSimulatorProcesses.value,
                                                  autodeleteSlowDevices: autodeleteSlowDevices.value,
                                                  codeCoveragePathEquivalence: codeCoveragePathEquivalence.value,
                                                  clearDerivedDataOnCompilationFailure: clearDerivedDataOnCompilationFailure.value,
                                                  skipResultMerge: skipResultMerge.value)

        let plugins: ModernConfiguration.Plugins
        if let pluginsData = pluginCustom.value {
            plugins = ModernConfiguration.Plugins(data: pluginsData, debug: debugPluginsFlag.value)
        } else {
            plugins = ModernConfiguration.Plugins(data: "", debug: false)
        }

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

        return ModernConfiguration(building: building, testing: testing, device: device, plugins: plugins, resultDestination: resultDestination, nodes: nodes, verbose: verboseFlag.value)
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
