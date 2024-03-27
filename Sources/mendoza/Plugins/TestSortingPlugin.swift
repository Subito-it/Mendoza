//
//  TestSortingPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

class TestSortingPlugin: Plugin<TestOrderInput, [TestCase]> {
    init(baseUrl: URL?, plugin: ModernConfiguration.Plugins? = nil) {
        super.init(name: "TestSortingPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
