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
    let dispatchOnLocalHostFlag = Flag(short: "l", long: "use_localhost", help: "Distribute tests on localhost as well")
    let verboseFlag = Flag(short: nil, long: "verbose", help: "Dump debug messages")
    let runHeadlessFlag = Flag(short: nil, long: "run_headless", help: "Run headless")

    let configurationPathField = Argument<URL>(name: "configuration_file", kind: .positional, optional: false, help: "Mendoza's configuration file path", autocomplete: .files("json"))
    let includePatternField = Argument<String>(name: "files", kind: .named(short: "f", long: "include_files"), optional: true, help: "Specify from which files UI tests should be extracted. Accepts wildcards and comma separated. e.g SBTA*.swift,SBTF*.swift. Default: '*.swift'", autocomplete: .files("swift"))
    let excludePatternField = Argument<String>(name: "files", kind: .named(short: "x", long: "exclude_files"), optional: true, help: "Specify which files should be skipped when extracting UI tests. Accepts wildcards and comma separated. e.g SBTA*.swift,SBTF*.swift. Default: ''", autocomplete: .files("swift"))
    let deviceNameField = Argument<String>(name: "name", kind: .named(short: "d", long: "device_name"), optional: true, help: "Device name to use to run tests. e.g. 'iPhone 8'")
    let deviceRuntimeField = Argument<String>(name: "version", kind: .named(short: "v", long: "device_runtime"), optional: true, help: "Device runtime to use to run tests. e.g. '13.0'")
    let timeoutField = Argument<Int>(name: "seconds", kind: .named(short: nil, long: "timeout"), optional: true, help: "Maximum allowed idle time (in seconds) in test standard output before dispatch process is automatically terminated. Default 120 seconds")
    let pluginCustomField = Argument<String>(name: "data", kind: .named(short: nil, long: "plugin_data"), optional: true, help: "A custom string that can be used to inject data to plugins")
    let failingTestsRetryCountField = Argument<Int>(name: "count", kind: .named(short: "r", long: "failure_retry"), optional: true, help: "Number of times a failing tests should be repeated")

    func run() -> Bool {
        do {
            let device: Device
            if let deviceName = deviceNameField.value, let deviceRuntime = deviceRuntimeField.value {
                device = Device(name: deviceName, runtime: deviceRuntime)
            } else {
                device = Device.defaultInit()
            }
            let timeout = timeoutField.value ?? 120
            let filePatterns = FilePatterns(commaSeparatedIncludePattern: includePatternField.value, commaSeparatedExcludePattern: excludePatternField.value)
            let failingTestsRetryCount = failingTestsRetryCountField.value ?? 0

            let test = try Test(configurationUrl: configurationPathField.value!,
                                device: device,
                                runHeadless: runHeadlessFlag.value,
                                filePatterns: filePatterns,
                                testTimeoutSeconds: timeout,
                                failingTestsRetryCount: failingTestsRetryCount,
                                dispatchOnLocalHost: dispatchOnLocalHostFlag.value,
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
