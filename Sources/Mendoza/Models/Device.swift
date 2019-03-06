//
//  Device.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

struct Device: Codable {
    let name: String
    let runtime: String
}

extension Device: DefaultInitializable {
    static func defaultInit() -> Device {
        return Device(name: "", runtime: "")
    }
}
