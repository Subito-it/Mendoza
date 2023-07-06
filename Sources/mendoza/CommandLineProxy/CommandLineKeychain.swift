//
//  CommandLineKeychain.swift
//  Mendoza
//
//  Created by Tomas Camin on 31/01/2019.
//

import Foundation

extension CommandLineProxy {
    struct Keychain {
        private let executer: Executer

        init(executer: Executer) {
            self.executer = executer
        }

        func unlock(password: String) throws {
            _ = try executer.execute("security unlock-keychain -p '\(password)' '\(executer.homePath)/Library/Keychains/login.keychain-db'")
        }
    }
}
