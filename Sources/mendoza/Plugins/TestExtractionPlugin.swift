//
//  TestExtractionPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

class TestExtractionPlugin: Plugin<TestExtractionInput, [TestCase]> {
    init(baseUrl: URL?, plugin: ModernConfiguration.Plugins? = nil) {
        super.init(name: "TestExtractionPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
