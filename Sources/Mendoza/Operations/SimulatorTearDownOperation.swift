//
//  SimulatorTearDownOperation.swift
//  Mendoza
//
//  Created by tomas on 21/03/2019.
//

import Foundation

class SimulatorTearDownOperation: BaseOperation<Void> {
    private let configuration: Configuration
    private let nodes: [Node]
    private let verbose: Bool
    private lazy var pool: ConnectionPool = {
        return makeConnectionPool(sources: nodes)
    }()
    private let resetSimulatorsOnCompletion = false
    
    init(configuration: Configuration, nodes: [Node], verbose: Bool) {
        self.configuration = configuration
        self.nodes = nodes
        self.verbose = verbose
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            try pool.execute { (executer, source) in
                let proxy = CommandLineProxy.Simulators(executer: executer, verbose: self.verbose)
                
                let bootedSimulators = try proxy.bootedSimulators()
                for simulator in bootedSimulators {
                    try proxy.terminateApp(identifier: self.configuration.buildBundleIdentifier, on: simulator)
                    try proxy.terminateApp(identifier: self.configuration.testBundleIdentifier, on: simulator)
                }
                
                if self.resetSimulatorsOnCompletion == true {
                    try? proxy.reset()
                }
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
