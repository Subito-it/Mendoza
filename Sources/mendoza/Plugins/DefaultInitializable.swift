//
//  DefaultInitializable.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

protocol DefaultInitializable: Codable {
    static func defaultInit() -> Self
}

extension Array: DefaultInitializable where Element: DefaultInitializable {
    static func defaultInit() -> [Element] {
        [Element.defaultInit()]
    }
}

extension Dictionary: DefaultInitializable where Key == String, Value: DefaultInitializable {
    static func defaultInit() -> [String: Value] {
        ["": Value.defaultInit()]
    }
}

extension Optional: DefaultInitializable where Wrapped: DefaultInitializable {
    static func defaultInit() -> Wrapped? {
        Wrapped.defaultInit()
    }
}
