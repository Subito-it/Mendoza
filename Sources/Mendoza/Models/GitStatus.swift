//
//  GitStatus.swift
//  Mendoza
//
//  Created by Tomas Camin on 28/01/2019.
//

import Foundation

struct GitStatus: Codable {
    let url: URL
    let branch: String
    let lastMessage: String
    let lastHash: String
}

extension GitStatus: DefaultInitializable {
    static func defaultInit() -> GitStatus {
        return GitStatus(url: URL(fileURLWithPath: ""), branch: "", lastMessage: "", lastHash: "")
    }
}
