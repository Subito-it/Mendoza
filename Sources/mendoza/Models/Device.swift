//
//  Device.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

struct Device: Codable, Hashable {
    let name: String
    let runtime: String
    let language: String?
    let locale: String?
}

extension Device: DefaultInitializable {
    static func defaultInit() -> Device {
        Device(name: "", runtime: "", language: nil, locale: nil)
    }
}

extension Device {
    func pointSize() -> CGSize {
        switch name {
        case "iPhone 4", "iPhone 4s": return CGSize(width: 320, height: 480)
        case "iPhone 5", "iPhone 5s", "iPhone 5c", "iPhone 5E": return CGSize(width: 320, height: 568)
        case "iPhone 6", "iPhone 6s", "iPhone 7", "iPhone 8": return CGSize(width: 375, height: 667)
        case "iPhone 6 Plus", "iPhone 6s Plus", "iPhone 7 Plus", "iPhone 8 Plus": return CGSize(width: 414, height: 736)
        case "iPhone X", "iPhone Xs", "iPhone 11 Pro": return CGSize(width: 375, height: 812)
        case "iPhone Xs Max", "iPhone Xʀ", "iPhone 11", "iPhone 11 Pro Max": return CGSize(width: 414, height: 896)
        case "iPhone 12": return CGSize(width: 390, height: 844)

        case "iPad Air": return CGSize(width: 768, height: 1024)
        case "iPad Air 2": return CGSize(width: 768, height: 1024)
        case "iPad Air (3rd generation)": return CGSize(width: 834, height: 1112)
        case "iPad Air (4th generation)": return CGSize(width: 820, height: 1180)
        case "iPad Air (5th generation)": return CGSize(width: 820, height: 1180)
        case "iPad (5th generation)": return CGSize(width: 768, height: 1024)
        case "iPad (6th generation)": return CGSize(width: 768, height: 1024)
        case "iPad (7th generation)": return CGSize(width: 810, height: 1080)
        case "iPad (8th generation)": return CGSize(width: 810, height: 1080)
        case "iPad (9th generation)": return CGSize(width: 810, height: 1080)
        case "iPad (10th generation)": return CGSize(width: 820, height: 1180)
        case "iPad Pro (9.7-inch)": return CGSize(width: 768, height: 1024)
        case "iPad Pro (10.5-inch)": return CGSize(width: 834, height: 1112)
        case "iPad Pro (11-inch)": return CGSize(width: 834, height: 1194)
        case "iPad Pro (11-inch) (2nd generation)": return CGSize(width: 834, height: 1194)
        case "iPad Pro (11-inch) (3rd generation)": return CGSize(width: 834, height: 1194)
        case "iPad Pro (11-inch) (4th generation)": return CGSize(width: 834, height: 1194)
        case "iPad Pro (12.9-inch)": return CGSize(width: 1024, height: 1366)
        case "iPad Pro (12.9-inch) (2nd generation)": return CGSize(width: 1024, height: 1366)
        case "iPad Pro (12.9-inch) (3rd generation)": return CGSize(width: 1024, height: 1366)
        case "iPad Pro (12.9-inch) (4th generation)": return CGSize(width: 1024, height: 1366)
        case "iPad Pro (12.9-inch) (5th generation)": return CGSize(width: 1024, height: 1366)
        case "iPad Pro (12.9-inch) (6th generation)": return CGSize(width: 1024, height: 1366)

        default: fatalError("Unsupported device name \(name)")
        }
    }
}
