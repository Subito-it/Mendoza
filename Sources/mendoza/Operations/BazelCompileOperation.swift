//
//  BazelCompileOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/10/26.
//

import Foundation

class BazelCompileOperation: BaseOperation<AppInfo> {
    private let test: BazelUITest
    private let building: Configuration.Building
    private let git: GitStatus?
    private let requiresCoverage: Bool
    private let preCompilationPlugin: PreCompilationPlugin
    private let postCompilationPlugin: PostCompilationPlugin

    private lazy var executer: Executer = self.makeLocalExecuter()

    init(test: BazelUITest, building: Configuration.Building, git: GitStatus?, requiresCoverage: Bool, preCompilationPlugin: PreCompilationPlugin, postCompilationPlugin: PostCompilationPlugin) {
        self.test = test
        self.building = building
        self.git = git
        self.requiresCoverage = requiresCoverage
        self.preCompilationPlugin = preCompilationPlugin
        self.postCompilationPlugin = postCompilationPlugin

        super.init()

        loggers = loggers.union([preCompilationPlugin.logger, postCompilationPlugin.logger])
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            if preCompilationPlugin.isInstalled {
                _ = try preCompilationPlugin.run(input: PluginVoid.defaultInit())
            }

            var compilationSucceeded = false
            defer {
                if postCompilationPlugin.isInstalled {
                    _ = try? postCompilationPlugin.run(input:
                        PostCompilationInput(compilationSucceeded: compilationSucceeded,
                                             outputPath: Path.testBundle.rawValue,
                                             git: self.git))
                }

                didEnd?(AppInfo.measure(executer: executer, buildBundleIdentifier: building.buildBundleIdentifier))
            }

            try test.workspace.with(executer: executer).build([test.label, test.hostLabel])

            let products = BazelTestProducts(test: test, executer: executer)
            try products.assemble(in: Path.testBundle.url, architecture: building.settings.architectures, profileDataPath: Path.logs.rawValue)

            try verifyInstrumentation()

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

    /// Whether the build collects coverage is up to the Bazel configuration, unlike xcodebuild where
    /// Mendoza enables it itself.
    private func verifyInstrumentation() throws {
        let executablePath = Path.testBundle.url.appendingPathComponent(test.app.fileName).appendingPathComponent(test.app.executableName).path
        let covmapSections = try executer.execute("otool -l '\(executablePath)' | grep -c 'sectname __llvm_covmap' || true")

        guard covmapSections == "0" else { return }

        let message = "\(test.app.fileName) is not instrumented for code coverage. Enable it in the Bazel configs passed to --bazel_config (--collect_code_coverage, --experimental_use_llvm_covmap) and make --instrumentation_filter match the app's targets"
        if requiresCoverage {
            throw Error("\(message): --individual_test_coverage and --test_covered_files need it", logger: executer.logger)
        } else {
            print("⚠️  \(message), the coverage report will be empty".yellow)
        }
    }
}
