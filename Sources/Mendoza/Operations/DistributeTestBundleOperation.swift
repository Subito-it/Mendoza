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

            print("ℹ️  Will distribute to \(nodes.count) nodes")

            while true {
                guard !isCancelled else { return }

                var readyNodes = Set<Node>()
                var missingNodes = Set<Node>()
                var distributionCompleted = false

                syncQueue.sync { [unowned self] in
                    readyNodes = distributedNodes.subtracting(sendingNodes)
                    missingNodes = self.nodes.subtracting(distributedNodes).subtracting(receivingNodes)

                    distributionCompleted = missingNodes.isEmpty && sendingNodes.isEmpty
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
                        executer = makeLocalExecuter()
                    case .remote:
                        let remoteExecuter = makeRemoteExecuter(node: source)
                        try remoteExecuter.connect()
                        executer = remoteExecuter
                    }
                    executers.append(executer)

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
                
                if readyNodes.isEmpty {
                    Thread.sleep(forTimeInterval: 1.0)
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
