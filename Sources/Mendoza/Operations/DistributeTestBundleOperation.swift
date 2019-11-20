//
//  DistributeTestBundleOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class DistributeTestBundleOperation: BaseOperation<Void> {
    private var executers = [Executer]()
    private let nodes: Set<Node>
    private let syncQueue = DispatchQueue(label: String(describing: DistributeTestBundleOperation.self))
    
    init(nodes: [Node]) {
        self.nodes = Set(nodes)
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            var distributedNodes = Set<Node>()
            var sendingNodes = Set<Node>()
            var receivingNodes = Set<Node>()
            
            let compilationNode: Node
            if let localNode = nodes.first(where: { AddressType(node: $0) == .local }) {
                compilationNode = localNode
            } else {
                compilationNode = Node.localhost()
            }
            distributedNodes.insert(compilationNode)
            
            print("ℹ️  Will distribute to \(self.nodes.count) nodes")
            
            while true  {
                guard !self.isCancelled else { return }
                
                var readyNodes = Set<Node>()
                var missingNodes = Set<Node>()
                var distributionCompleted = false
                
                syncQueue.sync { [unowned self] in
                    readyNodes = distributedNodes.subtracting(sendingNodes)
                    missingNodes = self.nodes.subtracting(distributedNodes).subtracting(receivingNodes)
                    
                    distributionCompleted = missingNodes.count == 0 && sendingNodes.count == 0
                }

                guard !distributionCompleted else { break }
                
                for source in readyNodes {
                    guard let destination = missingNodes.randomElement() else {
                        continue
                    }
                    
                    syncQueue.sync {
                        missingNodes.remove(destination)
                        sendingNodes.insert(source)
                        receivingNodes.insert(destination)
                    }
                    
                    let executer: Executer
                    switch AddressType(node: source) {
                    case .local:
                        executer = self.makeLocalExecuter()
                    case .remote:
                        let remoteExecuter = self.makeRemoteExecuter(node: source)
                        try remoteExecuter.connect()
                        executer = remoteExecuter
                    }
                    self.executers.append(executer)
                    
                    DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
                        do {
                            let buildPath = Path.testBundle.rawValue
                            print("🛫 `\(self.className)` \(source.address) -> \(destination.address)".bold)
                            try executer.rsync(sourcePath: "\(buildPath)/*", destinationPath: buildPath, on: destination)
                            print("🛬 `\(self.className)` \(source.address) -> \(destination.address)".bold)
                        } catch {
                            self.didThrow?(error)
                        }
                        
                        self.syncQueue.sync {
                            distributedNodes.insert(destination)
                            sendingNodes.remove(source)
                        }
                    }
                }
            }
            
            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }
    
    override func cancel() {
        if isExecuting {
            for executer in executers {
                executer.terminate()
            }
        }
        super.cancel()
    }
}
