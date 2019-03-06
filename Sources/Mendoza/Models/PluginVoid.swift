//
//  PluginVoid.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Foundation

enum PluginVoid: DefaultInitializable, CustomReflectable {
    case void
    
    var customMirror: Mirror { return Mirror(self, children: []) }
    static func defaultInit() -> PluginVoid { return .void }
    init(from decoder: Decoder) throws { self = PluginVoid.defaultInit() }
    func encode(to encoder: Encoder) throws {}
}
