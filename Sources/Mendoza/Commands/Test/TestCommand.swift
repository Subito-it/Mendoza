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
    
    let debugPlugins = Flag(short: nil, long: "plugin_debug", help: "Dump plugin invocation commands")
    let dispatchOnLocalHost = Flag(short: "l", long: "use_localhost", help: "Distribute tests on localhost as well")
    
    let configuration = Argument<URL>(name: "configuration_file", kind: .positional, optional: false, help: "Mendoza's configuration file path", autocomplete: .files("json"))
    let includePattern = Argument<String>(name: "files", kind: .named(short: "f", long: "include_files"), optional: true, help: "Specify from which files UI tests should be extracted. Accepts wildcards and comma separated. e.g SBTA*.swift,SBTF*.swift. Default: '*.swift'", autocomplete: .files("swift"))
    let excludePattern = Argument<String>(name: "files", kind: .named(short: "x", long: "exclude_files"), optional: true, help: "Specify which files should be skipped when extracting UI tests. Accepts wildcards and comma separated. e.g SBTA*.swift,SBTF*.swift. Default: ''", autocomplete: .files("swift"))
    let deviceName = Argument<String>(name: "name", kind: .named(short: "d", long: "device_name"), optional: false, help: "Device name to use to run tests. e.g. 'iPhone 8'")
    let deviceRuntime = Argument<String>(name: "version", kind: .named(short: "v", long: "device_runtime"), optional: false, help: "Device runtime to use to run tests. e.g. '12.1'")
    let timeoutField = Argument<Int>(name: "minutes", kind: .named(short: nil, long: "timeout"), optional: true, help: "Maximum allowed time (in minutes) before dispatch process is automatically terminated")
    let pluginCustomField = Argument<String>(name: "data", kind: .named(short: nil, long: "plugin_data"), optional: true, help: "A custom string that can be used to inject data to plugins")

    func run() -> Bool {
        let timeout = timeoutField.value ?? 180
        let device = Device(name: deviceName.value!, runtime: deviceRuntime.value!)
        let filePatterns = FilePatterns(commaSeparatedIncludePattern: includePattern.value, commaSeparatedExcludePattern: excludePattern.value)

        do {
            let test = try Test(configurationUrl: configuration.value!,
                                device: device,
                                filePatterns: filePatterns,
                                timeoutMinutes: timeout,
                                dispatchOnLocalHost: dispatchOnLocalHost.value,
                                pluginData: pluginCustomField.value,
                                debugPlugins: debugPlugins.value)
            
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
