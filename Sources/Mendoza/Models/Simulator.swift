//
//  Simulator.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

struct Simulator: Codable, Equatable {
    let id: String
    let name: String
    let device: Device
    
    static func ==(lhs: Simulator, rhs: Simulator) -> Bool {
        return lhs.id == rhs.id
    }
}
