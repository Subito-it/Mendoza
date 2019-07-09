//
//  LocalSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class LocalSetupOperation: BaseOperation<Void> {
    private let fileManager: FileManager
    private lazy var git = {
        return Git(executer: self.executer)
    }()
    private lazy var executer: Executer = {
        return makeLocalExecuter()
    }()
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    override func main() {
        guard !isCancelled else { return }
        
        do {
            didStart?()
            
            for path in Path.allCases {
                switch path {
                case .base, .build:
                    break
                case .logs, .temp, .testBundle, .results:
                    _ = try executer.execute("rm -rf '\(path.rawValue)' || true")
                }

                _ = try executer.execute("mkdir -p '\(path.rawValue)' || true")
            }
            
            didEnd?(())
        } catch {
            didThrow?(error)
        }
    }
    
    override func cancel() {
        if isExecuting {
            executer.terminate()
        }
        super.cancel()
    }
}
