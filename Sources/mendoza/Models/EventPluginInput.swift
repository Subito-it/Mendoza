//
//  EventPluginInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

struct EventPluginInput: Codable {
    let event: Event
    let device: Device
}

extension EventPluginInput: DefaultInitializable {
    static func defaultInit() -> EventPluginInput {
        EventPluginInput(event: Event.defaultInit(), device: Device.defaultInit())
    }
}
