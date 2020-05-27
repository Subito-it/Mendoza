//
//  Credentials.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Foundation

public struct Credentials: Codable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}
