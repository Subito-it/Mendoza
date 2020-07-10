//
//  Double+Time.swift
//  Mendoza
//
//  Created by tomas on 20/11/2019.
//

import Foundation

func hoursMinutesSeconds(in elapsed: Double) -> String {
    let hours = Int(elapsed / (60 * 60))
    let minutes = Int((elapsed - Double(hours) * 60 * 60) / 60)
    let seconds = Int(elapsed - Double(hours) * 60 * 60 - Double(minutes) * 60)

    var components = [String]()
    if hours > 0 { components.append("\(hours)h") }
    if minutes > 0 { components.append("\(minutes)m") }
    if seconds > 0 { components.append("\(seconds)s") }

    return components.joined(separator: " ")
}
