//
//  TearDownPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

class TearDownPlugin: Plugin<TestSessionResult, PluginVoid> {
    init(baseUrl: URL, plugin: (data: String?, debug: Bool) = (nil, false)) {
        super.init(name: "TearDownPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
