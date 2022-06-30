//
//  Node+Executer.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Foundation

extension Node {
    func makeExecuter(logger: ExecuterLogger?, environment: [String: String]) throws -> Executer {
        switch AddressType(node: self) {
        case .local:
            return LocalExecuter(logger: logger, environment: environment)
        case .remote:
            let connection = RemoteExecuter(node: self, logger: logger, environment: environment)
            try connection.connect()
            return connection
        }
    }
}
