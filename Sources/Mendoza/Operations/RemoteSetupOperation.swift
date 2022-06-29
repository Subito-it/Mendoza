//
//  RemoteSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class RemoteSetupOperation: BaseOperation<Void> {
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

            try pool.execute { executer, source in
                _ = try executer.execute("mkdir -p '\(Path.base.rawValue)' || true")
                
                let ramDisks = CommandLineProxy.RamDisk(executer: executer)
                try ramDisks.eject(name: Environment.ramDiskName, throwOnError: false)
                
                switch AddressType(node: source.node) {
                case .remote:
                    if let ramDiskSize = source.node.ramDiskSizeMB {
                        let ramDiskProxy = CommandLineProxy.RamDisk(executer: executer)
                        try ramDiskProxy.create(name: Environment.ramDiskName, sizeMB: ramDiskSize)
                    }
                case .local:
                    break // never create ram disk on local address because we already wrote critical files to Path.base
                }

                switch AddressType(node: source.node) {
                case .remote:
                    for path in Path.allCases.filter({ $0 != .base }) {
                        _ = try executer.execute("rm -rf '\(path.rawValue)' || true")
                        _ = try executer.execute("mkdir -p '\(path.rawValue)' || true")
                    }
                case .local:
                    break // Folders setup in LocalSetupOperation
                }

                _ = try executer.execute("touch '\(Path.base.url.appendingPathComponent(".metadata_never_index").path)'")
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
