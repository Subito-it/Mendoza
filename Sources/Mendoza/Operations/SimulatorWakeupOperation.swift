//
//  SimulatorWakeupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class SimulatorWakeupOperation: BaseOperation<Void> {
    private let nodes: [Node]
    private let runHeadless: Bool
    private let verbose: Bool
    private lazy var pool: ConnectionPool = {
        return makeConnectionPool(sources: nodes)
    }()
    
    init(nodes: [Node], runHeadless: Bool, verbose: Bool) {
        self.nodes = nodes
        self.runHeadless = runHeadless
        self.verbose = verbose
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            try pool.execute { (executer, node) in
                let simulators = CommandLineProxy.Simulators(executer: executer, verbose: self.verbose)
                
                if self.runHeadless == false {
                    try simulators.wakeUp()
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
