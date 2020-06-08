//
//  CompileOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class CompileOperation: BaseOperation<Void> {
    private let configuration: Configuration
    private let baseUrl: URL
    private let project: XcodeProject
    private let scheme: String
    private let preCompilationPlugin: PreCompilationPlugin
    private let postCompilationPlugin: PostCompilationPlugin
    private let sdk: XcodeProject.SDK
    private lazy var executer: Executer = {
        self.makeLocalExecuter()
    }()

    init(configuration: Configuration, baseUrl: URL, project: XcodeProject, scheme: String, preCompilationPlugin: PreCompilationPlugin, postCompilationPlugin: PostCompilationPlugin, sdk: XcodeProject.SDK) {
        self.configuration = configuration
        self.baseUrl = baseUrl
        self.project = project
        self.scheme = scheme
        self.preCompilationPlugin = preCompilationPlugin
        self.postCompilationPlugin = postCompilationPlugin
        self.sdk = sdk
        super.init()
        loggers = loggers.union([preCompilationPlugin.logger, postCompilationPlugin.logger])
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let schemeBackup = try project.backupScheme(name: configuration.scheme, baseUrl: baseUrl)
            try project.disableDebugger(schemeName: configuration.scheme)

            defer { try? project.restoreScheme(name: configuration.scheme, with: schemeBackup) }

            var xcodeBuild: XcodeBuildCommand
            var command = [String]()

            command.append("$(xcode-select -p)/usr/bin/xcodebuild")

            if let workspacePath = configuration.workspacePath {
                command.append("-workspace \(workspacePath)")
            } else {
                command.append("-project \(configuration.projectPath)")
            }

            command.append(contentsOf: [
                "build-for-testing",
                "-scheme '\(configuration.scheme)'",
                "-configuration \(configuration.buildConfiguration)",
                "-derivedDataPath '\(Path.build.rawValue)'",
                "-sdk '\(sdk.value)'",
                "-UseNewBuildSystem=\(configuration.compilation.useNewBuildSystem)",
                "-enableCodeCoverage YES",
                "COMPILER_INDEX_STORE_ENABLE=NO",
                "ONLY_ACTIVE_ARCH=\(configuration.compilation.onlyActiveArchitecture)",
                "VALID_ARCHS='\(configuration.compilation.architectures)'",
                configuration.compilation.buildSettings
            ])

            xcodeBuild = XcodeBuildCommand(arguments: command)

            if preCompilationPlugin.isInstalled {
                xcodeBuild = try preCompilationPlugin.run(input: PreCompilationInput(xcodeBuildCommand: command))
            }
            
            var compilationSucceeded = false

            defer {
                if postCompilationPlugin.isInstalled {
                    _ = try? postCompilationPlugin.run(input: PostCompilationInput(compilationSucceeded: compilationSucceeded))
                }

                didEnd?(())
            }

            #if DEBUG
            print(xcodeBuild.output)
            #endif

            _ = try executer.execute(xcodeBuild.output, currentUrl: baseUrl) { result, originalError in
                if result.output.contains("** TEST BUILD FAILED **") {
                    throw Error("Compilation failed!")
                } else {
                    throw originalError
                }
            }

            compilationSucceeded = true
        } catch {
            didThrow?(error)
        }
    }

    override func cancel() {
        if isExecuting {
            preCompilationPlugin.terminate()
            postCompilationPlugin.terminate()
            executer.terminate()
        }
        super.cancel()
    }
}
