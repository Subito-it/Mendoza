//
//  InitialSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class InitialSetupOperation: BaseOperation<Void> {
    private let nodes: [Node]
    private lazy var pool: ConnectionPool = {
        makeConnectionPool(sources: nodes)
    }()

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            try pool.execute { executer, _ in
                guard let maxUidProcessCountRaw = try executer.execute("sysctl kern.maxprocperuid").components(separatedBy: " ").last,
                    let maxUidProcessCount = Double(maxUidProcessCountRaw) else {
                    throw Error("Invalid maxprocperuid!")
                }

                let currentUidProcessCountRaw = try executer.execute("ps -u $(whoami) | awk 'END {print NR}'")
                guard let currentUidProcessCount = Double(currentUidProcessCountRaw) else {
                    throw Error("Invalid current procperuid!")
                }

                if currentUidProcessCount > maxUidProcessCount * 0.8 {
                    try CommandLineProxy.Simulators(executer: executer, verbose: false).reset()
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
