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
    private let accept: Bool

    init(configurationUrl: URL, name: String, accept: Bool) {
        self.configurationUrl = configurationUrl
        self.name = name
        self.accept = accept
    }

    func run() throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: configurationUrl.path) else {
            throw Error("Configuration fila path does not exist")
        }

        let pluginUrl = configurationUrl.deletingLastPathComponent().appendingPathComponent(Environment.pluginFolder)

        do {
            try fileManager.createDirectory(atPath: pluginUrl.path, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            throw Error("Unable to create directory \(error.debugDescription)")
        }

        switch name {
        case "event":
            if accept || Bariloche.ask("\nDo you want to install the `Test Event` plugin?\n".underline + "This plugin allows to perform actions (e.g. notifications) based on dispatching events") {
                try EventPlugin(baseUrl: pluginUrl).writeTemplate()
            }
        case "sorting":
            if accept || Bariloche.ask("\nDo you want to install the `Test Sorting` plugin?\n".underline + "This plugin allows to sort `XCTestCase`'s in order to optimize total execution time of test sessions") {
                try TestSortingPlugin(baseUrl: pluginUrl).writeTemplate()
            }
        case "extract":
            if accept || Bariloche.ask("\nDo you want to install the `Test Extraction` plugin?\n".underline + "This plugin allows to customize which `XCTestCase`'s test method should be distributed to testing nodes") {
                try TestExtractionPlugin(baseUrl: pluginUrl).writeTemplate()
            }
        case "precompilation":
            if accept || Bariloche.ask("\nDo you want to install the `Pre Compilation` plugin?\n".underline + "This plugin allows to run custom code before compilation starts") {
                try PreCompilationPlugin(baseUrl: pluginUrl).writeTemplate()
            }
        case "postcompilation":
            if accept || Bariloche.ask("\nDo you want to install the `Post Compilation` plugin?\n".underline + "This plugin allows to run custom code after compilation ends") {
                try PostCompilationPlugin(baseUrl: pluginUrl).writeTemplate()
            }
        case "teardown":
            if accept || Bariloche.ask("\nDo you want to install the `Tear Down` plugin?\n".underline + "This plugin allows to run custom code at the end of the dispatching process") {
                try TearDownPlugin(baseUrl: pluginUrl).writeTemplate()
            }
        default:
            throw Error("Unknown plugin `\(name)`!")
        }
    }
}
