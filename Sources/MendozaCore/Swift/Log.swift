//
//  Log.swift
//  MendozaCore
//
//  Created by Ashraf Ali on 15/06/2020.
//

import Foundation

func print(log string: String) {
    if let data = (string + "\n").data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}
