//
//  CompileOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class CompileOperation: BaseOperation<AppInfo> {
    private let configuration: Configuration
    private let git: GitStatus?
    private let baseUrl: URL
    private let project: XcodeProject
    private let scheme: String
    private let preCompilationPlugin: PreCompilationPlugin
    private let postCompilationPlugin: PostCompilationPlugin
    private let sdk: XcodeProject.SDK
    private let clearDerivedDataOnCompilationFailure: Bool
    
    private lazy var executer: Executer = {
        self.makeLocalExecuter()
    }()

    init(configuration: Configuration, git: GitStatus?, baseUrl: URL, project: XcodeProject, scheme: String, preCompilationPlugin: PreCompilationPlugin, postCompilationPlugin: PostCompilationPlugin, sdk: XcodeProject.SDK, clearDerivedDataOnCompilationFailure: Bool) {
        self.configuration = configuration
        self.git = git
        self.baseUrl = baseUrl
        self.project = project
        self.scheme = scheme
        self.preCompilationPlugin = preCompilationPlugin
        self.postCompilationPlugin = postCompilationPlugin
        self.sdk = sdk
        self.clearDerivedDataOnCompilationFailure = clearDerivedDataOnCompilationFailure
        
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

            let projectFlag: String
            if let workspacePath = configuration.workspacePath {
                projectFlag = "-workspace \(workspacePath)"
            } else {
                projectFlag = "-project \(configuration.projectPath)"
            }

            if preCompilationPlugin.isInstalled {
                _ = try preCompilationPlugin.run(input: PluginVoid.defaultInit())
            }
                        
            var compilationSucceeded = false
            defer {
                if postCompilationPlugin.isInstalled {
                    _ = try? postCompilationPlugin.run(input:
                                                        PostCompilationInput(compilationSucceeded: compilationSucceeded,
                                                                             outputPath: "\(Path.build.rawValue)/Build/Products",
                                                                             git: self.git))
                }

                var appSize: UInt64 = 0
                var dynamicFrameworkCount = 0
                if let executablePath = try? findExecutablePath(executer: executer, configuration: configuration) {
                    let executableUrl = URL(fileURLWithPath: executablePath)
                    let appUrl = executableUrl.deletingLastPathComponent()
                    appSize = (try? folderSize(appUrl.path)) ?? 0
                    let dynamicFrameworkUrl = appUrl.appendingPathComponent("Frameworks")
                    let dirContents = try? FileManager.default.contentsOfDirectory(atPath: dynamicFrameworkUrl.path)
                    dynamicFrameworkCount = dirContents?.filter { $0.hasSuffix(".framework") }.count ?? 0
                }

                didEnd?(AppInfo(size: appSize, dynamicFrameworkCount: dynamicFrameworkCount))
            }

            let command: String
            switch sdk {
            case .ios:
                command = "$(xcode-select -p)/usr/bin/xcodebuild \(projectFlag) -scheme '\(configuration.scheme)' -configuration \(configuration.buildConfiguration) -derivedDataPath '\(Path.build.rawValue)' -sdk 'iphonesimulator' COMPILER_INDEX_STORE_ENABLE=NO SWIFT_INDEX_STORE_ENABLE=NO MTL_ENABLE_INDEX_STORE=NO ONLY_ACTIVE_ARCH=\(configuration.compilation.onlyActiveArchitecture) VALID_ARCHS='\(configuration.compilation.architectures)' \(configuration.compilation.buildSettings) -UseNewBuildSystem=\(configuration.compilation.useNewBuildSystem) -enableCodeCoverage YES build-for-testing 2>&1"
            case .macos:
                command = "$(xcode-select -p)/usr/bin/xcodebuild \(projectFlag) -scheme '\(configuration.scheme)' -configuration \(configuration.buildConfiguration) -derivedDataPath '\(Path.build.rawValue)' -sdk 'macosx' COMPILER_INDEX_STORE_ENABLE=NO SWIFT_INDEX_STORE_ENABLE=NO MTL_ENABLE_INDEX_STORE=NO ONLY_ACTIVE_ARCH=\(configuration.compilation.onlyActiveArchitecture) VALID_ARCHS='\(configuration.compilation.architectures)' \(configuration.compilation.buildSettings) -UseNewBuildSystem=\(configuration.compilation.useNewBuildSystem) -enableCodeCoverage YES build-for-testing 2>&1"
            }
            
            for iteration in 0...1 {
                let shouldRetryCompilation = clearDerivedDataOnCompilationFailure && iteration == 0
                
                do {
                    let output = try executer.execute(command, currentUrl: baseUrl)
                        
                    let compilationDidFail = output.contains("** TEST BUILD FAILED **")
                    
                    if compilationDidFail && shouldRetryCompilation {
                        clearDerivedData(executer: executer)
                    } else if compilationDidFail {
                        throw Error("Compilation failed!")
                    } else {
                        compilationSucceeded = true
                        return
                    }
                } catch {
                    if shouldRetryCompilation {
                        clearDerivedData(executer: executer)
                    } else {
                        throw error
                    }
                }
            }
            
            throw Error("Compilation failed!")
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
    
    private func clearDerivedData(executer: Executer) {
        _ = try? executer.execute("rm -rf '\(Path.build.rawValue)'")
        print("💣 Compilation did fail, clearing derived data".red)
    }
        
    private func folderSize(_ path: String) throws -> UInt64 {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        
        var totalSize: UInt64 = 0
        for content in contents {
            do {
                let fullContentPath = path + "/" + content
                let attributes = try FileManager.default.attributesOfItem(atPath: fullContentPath)
                
                guard let contentType = attributes[.type] as? FileAttributeType else { continue }
                
                switch contentType {
                case .typeRegular:
                    totalSize += attributes[.size] as? UInt64 ?? 0
                case .typeDirectory:
                    totalSize += try folderSize(fullContentPath)
                default:
                    continue
                }
            } catch _ {
                continue
            }
        }
        
        return totalSize
    }
}
