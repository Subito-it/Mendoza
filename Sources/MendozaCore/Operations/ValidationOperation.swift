//
//  ValidationOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 18/02/2019.
//

import Foundation

class ValidationOperation: BaseOperation<Void> {
    private let configuration: Configuration
    private lazy var executer: Executer = {
        makeLocalExecuter()
    }()

    private lazy var pool: ConnectionPool = {
        makeConnectionPool(sources: configuration.nodes)
    }()

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    private var isRunningViaXCTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            let validator = ConfigurationValidator(configuration: configuration)
            defer { loggers = loggers.union(validator.loggers) }
            try validator.validate()

            guard let compilingSwiftVersion = try executer.execute("swiftc --version").capturedGroups(withRegexString: #"swiftlang(.*)\)"#).first else {
                throw Error("Failed fetching swift version, expecting 'swiftlang(.*)' when running `swiftc --version`", logger: executer.logger)
            }

            try pool.execute { executer, _ in
                guard let remoteSwiftVersion = try executer.execute("swiftc --version").capturedGroups(withRegexString: #"swiftlang(.*)\)"#).first else {
                    throw Error("Failed fetching swift version, expecting 'swiftlang(.*)' when running `swiftc --version`", logger: executer.logger)
                }

                guard remoteSwiftVersion == compilingSwiftVersion else {
                    throw Error("Incompatible swift compiler version, check that Xcode's versions match on all nodes.\n\nExpecting:\n`\(compilingSwiftVersion)`\n\nGot:\n`\(remoteSwiftVersion)` on \(executer.address)", logger: executer.logger)
                }

                if !self.isRunningViaXCTests {
                    let remoteMendozaVersion = try executer.execute("mendoza --version")
                    guard Mendoza.version == remoteMendozaVersion else {
                        throw Error("Incompatible mendoza versions, check that Mendoza's versions match on all nodes.\n\nExpecting:\n`\(Mendoza.version)`\n\nGot:\n`\(remoteMendozaVersion)` on \(executer.address)", logger: executer.logger)
                    }
                }

                try self.checkDependencies(executer: executer)
            }

            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }

    private func checkDependencies(executer: Executer) throws {
        _ = try executer.execute("whereis xcode-select") { _, _ in
            throw Error("`xcode-select` missing on \(executer.address). To use UI Testing dispatcher you'll need to install Xcode's Command Line Tools by manually launching Xcode or by running `gem install xcode-install; xcversion install-cli-tools`")
        }

        _ = try executer.execute("whereis xcversion") { _, _ in throw
            Error("`xcode-install` missing on \(executer.address). To use UI Testing dispatcher you'll install xcode-install (https://github.com/KrauseFx/xcode-install)")
        }
    }

    override func cancel() {
        if isExecuting {
            executer.terminate()
            pool.terminate()
        }
        super.cancel()
    }
}
