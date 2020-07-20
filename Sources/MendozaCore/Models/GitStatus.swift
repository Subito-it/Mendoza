//
//  GitStatus.swift
//  Mendoza
//
//  Created by Tomas Camin on 28/01/2019.
//

import Foundation

public struct GitStatus: Codable {
    public let url: URL
    let branch: String
    let commitMessage: String
    let commitHash: String
}

extension GitStatus: DefaultInitializable {
    public static func defaultInit() -> GitStatus {
        return GitStatus(url: URL(fileURLWithPath: ""), branch: "", commitMessage: "", commitHash: "")
    }
}
