//
//  AppInfo.swift
//  Mendoza
//
//  Created by Jessica on 16/06/21.
//

import Foundation

struct AppInfo: Codable {
    let size: UInt64
    let dynamicFrameworkCount: Int
}

extension AppInfo: DefaultInitializable {
    static func defaultInit() -> AppInfo {
        AppInfo(size: 0, dynamicFrameworkCount: 0)
    }
}
