//
//  TearDownPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

public class TearDownPlugin: Plugin<TestSessionResult, PluginVoid> {
    public init(baseUrl: URL, plugin: (data: String?, debug: Bool) = (nil, false)) {
        super.init(name: "TearDownPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
