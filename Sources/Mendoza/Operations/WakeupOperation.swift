//
//  WakeupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

// This task sends a `pmset schedule wake` to nodes. This appears to be useful when using macbooks with closed lids as remote nodes

class WakeupOperation: BaseOperation<Void> {
    private let nodes: [Node]
    private lazy var pool: ConnectionPool = {
        return makeConnectionPool(sources: nodes)
    }()
    
    init(nodes: [Node]) {
        self.nodes = nodes
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
                        
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
            let date = formatter.string(from: Date(timeIntervalSinceNow: 30.0))

            try pool.execute { (executer, source) in
                let node = source.node
                
                guard AddressType(node: node) == .remote else { return }
                guard let password = node.administratorPassword ?? nil else {
                    print("ℹ️  Skipping wake up for node `\(node.address)` because no administrator password was provided".bold)
                    return
                }
                
                executer.logger?.addBlackList(password)
                _ = try executer.execute("echo '\(password)' | sudo -S pmset schedule wake '\(date)'")
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
