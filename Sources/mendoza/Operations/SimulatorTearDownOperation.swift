//
//  SimulatorTearDownOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 21/03/2019.
//

import Foundation

class SimulatorTearDownOperation: BaseOperation<Void> {
    private let nodes: [Node]
    private let verbose: Bool
    private lazy var pool: ConnectionPool = makeConnectionPool(sources: nodes)

    init(nodes: [Node], verbose: Bool) {
        self.nodes = nodes
        self.verbose = verbose
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            try pool.execute { _, _ in
                // Do nothing
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
