//
//  TestDistributionPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

class TestDistributionPlugin: Plugin<TestOrderInput, [[EstimatedTestCase]]> {
    init(baseUrl: URL, plugin: (data: String?, debug: Bool) = (nil, false)) {
        super.init(name: "TestDistributionPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
