//
//  Node+Executer.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Foundation

extension Node {
    func makeExecuter(logger: ExecuterLogger?) throws -> Executer {
        switch AddressType(node: self) {
        case .local:
            return LocalExecuter(logger: logger)
        case .remote:
            let connection = RemoteExecuter(node: self, logger: logger)
            try connection.connect()
            return connection
        }
    }
}
