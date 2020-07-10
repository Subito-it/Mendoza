//
//  PluginInit.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Bariloche
import Foundation

struct PluginInit {
    private let configurationUrl: URL
    private let name: String

    init(configurationUrl: URL, name: String) {
        self.configurationUrl = configurationUrl
        self.name = name
    }

    func run() throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: configurationUrl.path) else {
            throw Error("Configuration fila path does not exist")
        }

        let currentUrl = configurationUrl.deletingLastPathComponent()

        switch name {
        case "event":
            if Bariloche.ask("\nDo you want to install the `Test Event` plugin?\n".underline + "This plugin allows to perform actions (e.g. notifications) based on dispatching events") {
                try EventPlugin(baseUrl: currentUrl).writeTemplate()
            }
        case "sorting":
            if Bariloche.ask("\nDo you want to install the `Test Sorting` plugin?\n".underline + "This plugin allows to sort `XCTestCase`'s in order to optimize total execution time of test sessions") {
                try TestSortingPlugin(baseUrl: currentUrl).writeTemplate()
            }
        case "extract":
            if Bariloche.ask("\nDo you want to install the `Test Extraction` plugin?\n".underline + "This plugin allows to customize which `XCTestCase`'s test method should be distributed to testing nodes") {
                try TestExtractionPlugin(baseUrl: currentUrl).writeTemplate()
            }
        case "precompilation":
            if Bariloche.ask("\nDo you want to install the `Pre Compilation` plugin?\n".underline + "This plugin allows to run custom code before compilation starts") {
                try PreCompilationPlugin(baseUrl: currentUrl).writeTemplate()
            }
        case "postcompilation":
            if Bariloche.ask("\nDo you want to install the `Post Compilation` plugin?\n".underline + "This plugin allows to run custom code after compilation ends") {
                try PostCompilationPlugin(baseUrl: currentUrl).writeTemplate()
            }
        case "teardown":
            if Bariloche.ask("\nDo you want to install the `Tear Down` plugin?\n".underline + "This plugin allows to run custom code at the end of the dispatching process") {
                try TearDownPlugin(baseUrl: currentUrl).writeTemplate()
            }
        default:
            throw Error("Unknown plugin `\(name)`!")
        }
    }
}
