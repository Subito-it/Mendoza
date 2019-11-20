//
//  TearDownOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class TearDownOperation: BaseOperation<Void> {
    var testSessionResult: TestSessionResult?
    
    private lazy var pool: ConnectionPool = {
        return makeConnectionPool(sources: configuration.nodes)
    }()
    private let configuration: Configuration
    private let plugin: TearDownPlugin
    
    init(configuration: Configuration, plugin: TearDownPlugin) {
        self.configuration = configuration
        self.plugin = plugin
        super.init()
        loggers.insert(plugin.logger)
    }

    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            try pool.execute { (executer, source) in                
                if AddressType(node: source.node) == .remote {
                    _ = try? executer.execute("rm -rf '\(Path.base.rawValue)/*'")
                }
            }
            
            if plugin.isInstalled {
                guard let testSessionResult = testSessionResult else { fatalError("💣 Required fields not set") }
                _ = try plugin.run(input: testSessionResult)
            }

            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }
        
    override func cancel() {
        if isExecuting {
            pool.terminate()
        }
        super.cancel()
    }
}
