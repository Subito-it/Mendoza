//
//  LocalSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class LocalSetupOperation: BaseOperation<Void> {
    private let fileManager: FileManager
    private let clearDerivedDataOnCompilationFailure: Bool
    
    private lazy var git = {
        Git(executer: self.executer)
    }()

    private lazy var executer: Executer = {
        makeLocalExecuter()
    }()

    init(fileManager: FileManager = .default, clearDerivedDataOnCompilationFailure: Bool) {
        self.fileManager = fileManager
        self.clearDerivedDataOnCompilationFailure = clearDerivedDataOnCompilationFailure
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            if clearDerivedDataOnCompilationFailure {
                for path in Path.allCases {
                    switch path {
                    case .base, .build:
                        break
                    case .testBundle:
                        _ = try executer.execute("rm -rf '\(path.rawValue)/'*.xctestrun || true")
                    case .temp, .logs, .results:
                        _ = try executer.execute("rm -rf '\(path.rawValue)' || true")
                    }
                }
            } else {
                _ = try executer.execute("rm -rf '\(Path.base.rawValue)' || true")
            }

            for path in Path.allCases {
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
