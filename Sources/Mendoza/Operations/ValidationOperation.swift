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
        return makeLocalExecuter()
    }()
    private lazy var pool: ConnectionPool = {
        return makeConnectionPool(sources: configuration.nodes)
    }()
    
    init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            let validator = ConfigurationValidator(configuration: configuration)
            defer { loggers = loggers.union(validator.loggers) }
            try validator.validate()
            
            guard let compilingSwiftVersion = try executer.execute("swiftc --version").capturedGroups(withRegexString: #"swiftlang(.*)\)"#).first else { throw Error("Failed fetching swift version, expecting 'swiftlang(.*)' when running `swiftc --version`", logger: executer.logger) }
            
            try pool.execute { (executer, source) in
                guard let remoteSwiftVersion = try executer.execute("swiftc --version").capturedGroups(withRegexString: #"swiftlang(.*)\)"#).first else { throw Error("Failed fetching swift version, expecting 'swiftlang(.*)' when running `swiftc --version`", logger: executer.logger) }
                
                guard remoteSwiftVersion == compilingSwiftVersion else {
                    throw Error("Incompatible swift compiler version, check that Xcode's versions match.\n\nExpecting:\n`\(compilingSwiftVersion)`\n\nGot:\n`\(remoteSwiftVersion)`", logger: executer.logger)
                }
                
                let remoteMendozaVersion = try executer.execute("mendoza --version")
                guard Mendoza.version == remoteMendozaVersion else {
                    throw Error("Incompatible mendoza versions.\n\nExpecting:\n`\(Mendoza.version)`\n\nGot:\n`\(remoteMendozaVersion)`", logger: executer.logger)
                }
                
                try self.checkDependencies(executer: executer)
            }
                        
            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }
    
    private func checkDependencies(executer: Executer) throws {        
        _ = try executer.execute("whereis xcversion") { _, _ in throw Error("To use UI Testing dispatcher you'll install xcode-install (https://github.com/KrauseFx/xcode-install)") }
    }
    
    override func cancel() {
        if isExecuting {
            executer.terminate()
            pool.terminate()
        }
        super.cancel()
    }
}
