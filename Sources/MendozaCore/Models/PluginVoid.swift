//
//  PluginVoid.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Foundation

public enum PluginVoid: DefaultInitializable, CustomReflectable {
    case void

    public var customMirror: Mirror { return Mirror(self, children: []) }
    public static func defaultInit() -> PluginVoid { return .void }
    public init(from _: Decoder) throws { self = PluginVoid.defaultInit() }
    public func encode(to _: Encoder) throws {}
}
