//
//  EventPluginInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

public struct EventPluginInput: Codable {
    let event: Event
    let device: Device
}

extension EventPluginInput: DefaultInitializable {
    public static func defaultInit() -> EventPluginInput {
        return EventPluginInput(event: Event.defaultInit(), device: Device.defaultInit())
    }
}
