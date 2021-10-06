//
//  Simulator.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

struct Simulator: Codable, Hashable {
    let id: String
    let name: String
    let device: Device

    static func == (lhs: Simulator, rhs: Simulator) -> Bool {
        lhs.id == rhs.id
    }
}

extension Simulator {
    static func defaultInit() -> Simulator {
        Simulator(id: "", name: "", device: .defaultInit())
    }
}
