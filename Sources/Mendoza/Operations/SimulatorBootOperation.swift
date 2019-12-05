//
//  SimulatorBootOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class SimulatorBootOperation: BaseOperation<Void> {
    var simulators: [(simulator: Simulator, node: Node)]?
    
    private let verbose: Bool
    private let runHeadless: Bool
    private lazy var pool: ConnectionPool<Simulator> = {
        guard let simulators = simulators else { fatalError("💣 Required fields not set") }
        return makeConnectionPool(sources: simulators.map { (node: $0.node, value: $0.simulator) })
    }()
    
    init(runHeadless: Bool, verbose: Bool) {
        self.runHeadless = runHeadless
        self.verbose = verbose
    }

    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()

            try pool.execute { (executer, source) in
                guard self.runHeadless == false else { return }
                
                let proxy = CommandLineProxy.Simulators(executer: executer, verbose: self.verbose)
                
                try proxy.boot(simulator: source.value)
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
