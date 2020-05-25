//
//  Double+Time.swift
//  Mendoza
//
//  Created by tomas on 20/11/2019.
//

import Foundation

func formatTime(duration elapsed: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .full

    let formattedString = formatter.string(from: TimeInterval(elapsed))!

    return formattedString
}
