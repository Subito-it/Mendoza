//
//  RemoteConfiguration.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation
import KeychainAccess

struct RemoteConfiguration: Codable {
    let resultDestination: ConfigurationResultDestination
    let nodes: [Node]
}
