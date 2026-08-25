//
//  PluginVoid.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Foundation

/// Input or output of a plugin that has none. Encodes to `{}`, which is what the `input` key
/// of the envelope carries for plugins that take no input.
enum PluginVoid: DefaultInitializable {
    case void

    static func defaultInit() -> PluginVoid {
        .void
    }

    init(from _: Decoder) throws {
        self = PluginVoid.defaultInit()
    }

    func encode(to _: Encoder) throws {}
}
