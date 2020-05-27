//
//  TestExtractionPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

public class TestExtractionPlugin: Plugin<TestExtractionInput, [TestCase]> {
    public init(baseUrl: URL, plugin: (data: String?, debug: Bool) = (nil, false)) {
        super.init(name: "TestExtractionPlugin", baseUrl: baseUrl, plugin: plugin)
    }
}
