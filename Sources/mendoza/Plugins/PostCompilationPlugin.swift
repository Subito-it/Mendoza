//
//  PostCompilationPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 28/01/2019.
//

import Foundation

class PostCompilationPlugin: Plugin<PostCompilationInput, PluginVoid> {
    init(baseUrl: URL, plugin: (data: String?, debug: Bool) = (nil, false)) {
        super.init(name: "PostCompilationPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
