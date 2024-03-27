//
//  CommandTest.swift
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

    let configurationPathField = Argument<URL>(name: "configuration_file", kind: .positional, optional: false, help: "Mendoza's configuration file path", autocomplete: .files("json"))
    let includePatternField = Argument<String>(name: "files", kind: .named(short: "f", long: "include_files"), optional: true, help: "Specify from which files UI tests should be extracted. Accepts wildcards and comma separated values. e.g SBTA*.swift,SBTF*.swift. Default: '*.swift'", autocomplete: .files("swift"))
    let excludePatternField = Argument<String>(name: "files", kind: .named(short: "x", long: "exclude_files"), optional: true, help: "Specify which files should be skipped when extracting UI tests. Accepts wildcards and comma separated values. e.g SBTA*.swift,SBTF*.swift. Default: ''", autocomplete: .files("swift"))
    let deviceNameField = Argument<String>(name: "name", kind: .named(short: "d", long: "device_name"), optional: true, help: "Device name to use to run tests. e.g. 'iPhone 8'")
    let deviceRuntimeField = Argument<String>(name: "version", kind: .named(short: "v", long: "device_runtime"), optional: true, help: "Device runtime to use to run tests. e.g. '13.0'")
    let deviceLanguage = Argument<String>(name: "language", kind: .named(short: nil, long: "device_language"), optional: true, help: "Device language. e.g. 'en-EN'")
    let deviceLocale = Argument<String>(name: "locale", kind: .named(short: nil, long: "device_locale"), optional: true, help: "Device locale. e.g. 'en_US'")
    let autodeleteSlowDevices = Flag(short: nil, long: "delete_slow_devices", help: "Automatically delete devices that took longer than expected to start dispatching tests. When such a case is detected on a node all its devices will be deleted which is the only workaround to avoid this delay to happen in future test dispatches")
    let maximumStdOutIdleTime = Argument<Int>(name: "seconds", kind: .named(short: nil, long: "stdout_timeout"), optional: true, help: "Maximum allowed idle time (in seconds) in standard output before test is automatically terminated")
    let maximumTestExecutionTime = Argument<Int>(name: "seconds", kind: .named(short: nil, long: "max_execution_time"), optional: true, help: "Maximum execution time (in seconds) before test fails with a timeout error")
    let pluginCustomField = Argument<String>(name: "data", kind: .named(short: nil, long: "plugin_data"), optional: true, help: "A custom string that can be used to inject data to plugins")
    let failingTestsRetryCountField = Argument<Int>(name: "count", kind: .named(short: "r", long: "failure_retry"), optional: true, help: "Number of times a failing tests should be repeated")
    let codeCoveragePathEquivalence = Argument<String>(name: "path", kind: .named(short: nil, long: "llvm_cov_equivalence_path"), optional: true, help: "Path equivalence path passed to 'llvm-cov show' when extracting code coverage (<from>,<to>)")
    let xcodeBuildNumber = Argument<String>(name: "number", kind: .named(short: nil, long: "xcode_buildnumber"), optional: true, help: "Build number of the Xcode version to use (e.g. 12E507)")
    let skipResultMerge = Flag(short: nil, long: "skip_result_merge", help: "Skip xcresult merge (keep one xcresult per test in the result folder)")
    let clearDerivedDataOnCompilationFailure = Flag(short: nil, long: "clear_derived_data_on_failure", help: "On compilation failure derived data will be cleared and compilation will be retried once")
    let xcresultBlobThresholdKB = Argument<Int>(name: "size", kind: .named(short: nil, long: "xcresult_blob_threshold_kb"), optional: true, help: "Delete data blobs larger than the specified threshold")
    let excludeNodes = Argument<String>(name: "nodes", kind: .named(short: nil, long: "exclude_nodes"), optional: true, help: "Specify which nodes (by name or address) specified in the configuration should be excluded from the dispatch. Accepts comma separated values. Default: ''")
    let killSimulatorProcesses = Flag(short: nil, long: "kill_sim_procs", help: "Automatically kill Simulator's CPU intensive processes")

    func run() -> Bool {
        do {
            var device: Device?
            if let deviceName = deviceNameField.value, let deviceRuntime = deviceRuntimeField.value {
                device = Device(name: deviceName, runtime: deviceRuntime, language: deviceLanguage.value, locale: deviceLocale.value)
            }

            let filePatterns = FilePatterns(commaSeparatedIncludePattern: includePatternField.value, commaSeparatedExcludePattern: excludePatternField.value)

            let test = try Test(configurationUrl: configurationPathField.value!, // swiftlint:disable:this force_unwrapping
                                device: device,
                                skipResultMerge: skipResultMerge.value,
                                clearDerivedDataOnCompilationFailure: clearDerivedDataOnCompilationFailure.value,
                                filePatterns: filePatterns,
                                maximumStdOutIdleTime: maximumStdOutIdleTime.value,
                                maximumTestExecutionTime: maximumTestExecutionTime.value,
                                failingTestsRetryCount: failingTestsRetryCountField.value ?? 0,
                                codeCoveragePathEquivalence: codeCoveragePathEquivalence.value,
                                xcodeBuildNumber: xcodeBuildNumber.value,
                                autodeleteSlowDevices: autodeleteSlowDevices.value,
                                excludedNodes: excludeNodes.value,
                                xcresultBlobThresholdKB: xcresultBlobThresholdKB.value,
                                killSimulatorProcesses: killSimulatorProcesses.value,
                                pluginData: pluginCustomField.value,
                                debugPlugins: debugPluginsFlag.value,
                                verbose: verboseFlag.value)

            test.didFail = { [weak self] in self?.handleError($0) }
            try test.run()
        } catch {
            handleError(error)
        }

        return true
    }

    private func handleError(_ error: Swift.Error) {
        print(error.localizedDescription)

        if !(error is Error) {
            print("\n\(String(describing: error))")
        }

        exit(-1)
    }
}
