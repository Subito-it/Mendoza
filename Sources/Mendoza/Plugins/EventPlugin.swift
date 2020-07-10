//
//  EventPlugin.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

class EventPlugin: Plugin<EventPluginInput, PluginVoid> {
    init(baseUrl: URL, plugin: (data: String?, debug: Bool) = (nil, false)) {
        super.init(name: "EventPlugin", baseUrl: baseUrl, plugin: plugin)
    }

    func run(event: Event, device: Device) throws {
        guard isInstalled else { return }
        _ = try super.run(input: EventPluginInput(event: event, device: device))
    }
}
