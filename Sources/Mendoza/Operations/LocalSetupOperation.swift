//
//  LocalSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class LocalSetupOperation: BaseOperation<Void> {
    private let fileManager: FileManager
    private let administratorPassword: String?
    private let clearDerivedDataOnCompilationFailure: Bool
    
    private lazy var git = {
        Git(executer: self.executer)
    }()

    private lazy var executer: Executer = {
        makeLocalExecuter()
    }()

    init(fileManager: FileManager = .default, clearDerivedDataOnCompilationFailure: Bool, administratorPassword: String?) {
        self.fileManager = fileManager
        self.clearDerivedDataOnCompilationFailure = clearDerivedDataOnCompilationFailure
        self.administratorPassword = administratorPassword
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            for path in Path.allCases {
                switch path {
                case .base, .build:
                    break
                case .testBundle:
                    // Reuse derived data
                    if !clearDerivedDataOnCompilationFailure {
                        _ = try executer.execute("rm -rf '\(path.rawValue)' || true")
                    } else {
                        _ = try executer.execute("rm -rf '\(path.rawValue)/'*.xctestrun || true")
                    }
                case .logs, .temp, .results:
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
