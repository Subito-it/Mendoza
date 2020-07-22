//
//  PreCompilationPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 28/01/2019.
//

import Foundation

public class PreCompilationPlugin: Plugin<PreCompilationInput, XcodeBuildCommand> {
    public init(baseUrl: URL, plugin: (data: String?, debug: Bool) = (nil, false)) {
        super.init(name: "PreCompilationPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
