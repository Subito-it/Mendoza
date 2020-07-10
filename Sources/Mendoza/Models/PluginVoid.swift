//
//  PluginVoid.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Foundation

enum PluginVoid: DefaultInitializable, CustomReflectable {
    case void

    var customMirror: Mirror { Mirror(self, children: []) }
    static func defaultInit() -> PluginVoid { .void }
    init(from _: Decoder) throws { self = PluginVoid.defaultInit() }
    func encode(to _: Encoder) throws {}
}
