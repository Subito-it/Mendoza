//
//  MacOsValidationOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/03/2019.
//

import Foundation

class MacOsValidationOperation: BaseOperation<Void> {
    private let configuration: Configuration
    private lazy var pool: ConnectionPool = {
        return makeConnectionPool(sources: configuration.nodes)
    }()
    private let syncQueue = DispatchQueue(label: String(describing: MacOsValidationOperation.self))
    
    init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            var versions = Set<String>()
            
            try pool.execute { (executer, source) in
                let macOsVersion = try executer.execute("defaults read loginwindow SystemVersionStampAsString")
                
                guard macOsVersion.count > 0 else { throw Error("Failed getting mac os version") }
                
                self.syncQueue.sync { _ = versions.insert(macOsVersion) }
            }
            
            guard versions.count == 1 else {
                throw Error("Multiple versions of mac os found: `\(versions.joined(separator: "`, `"))`")
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
