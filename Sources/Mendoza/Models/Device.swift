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

extension Device {
    func pointSize() -> CGSize  {
        switch self.name {
        case "iPhone 4", "iPhone 4s": return CGSize(width: 320, height: 480)
        case "iPhone 5", "iPhone 5s", "iPhone 5c", "iPhone 5E": return CGSize(width: 320, height: 568)
        case "iPhone 6", "iPhone 6s", "iPhone 7", "iPhone 8": return CGSize(width: 375, height: 667)
        case "iPhone 6 Plus", "iPhone 6s Plus", "iPhone 7 Plus", "iPhone 8 Plus": return CGSize(width: 414, height: 736)
        case "iPhone X", "iPhone Xs", "iPhone 11 Pro": return CGSize(width: 375, height: 812)
        case "iPhone Xs Max", "iPhone Xʀ", "iPhone 11", "iPhone 11 Pro Max": return CGSize(width: 414, height: 896)
            
        case "iPad Air": return CGSize(width: 768, height: 1024)
        case "iPad Air (3rd generation)": return CGSize(width: 414, height: 896)
        case "iPad Air 2": return CGSize(width: 768, height: 1024)
        case "iPad (5th generation)": return CGSize(width: 768, height: 1024)
        case "iPad (6th generation)": return CGSize(width: 768, height: 1024)
        case "iPad Pro (9.7-inch)": return CGSize(width: 768, height: 1024)
        case "iPad Pro (10.5-inch)": return CGSize(width: 834, height: 1112)
        case "iPad Pro (11-inch)": return CGSize(width: 834, height: 1194)
        case "iPad Pro (12.9-inch)": return CGSize(width: 1024, height: 1366)
        case "iPad Pro (12.9-inch) (2nd generation)": return CGSize(width: 1024, height: 1366)
            
        default: fatalError("Unsupported device name \(name)")
        }
    }
}
