//
//  ExecuterEnvironment.swift
//  Mendoza
//
//  Created by tomas.camin on 11/07/22.
//

import Foundation

enum ExecuterEnvironment {
    static func exportsCommand(for environment: [String: String]?) -> String {
        guard let environment = environment else {
            return ""
        }

        let escapeValue: (String) -> String = { value in "$'\(value.replacingOccurrences(of: "'", with: "\'"))'" }
        return environment.map { k, v in "export \(k)=\(escapeValue(v));" }.joined(separator: " ")
    }
}
