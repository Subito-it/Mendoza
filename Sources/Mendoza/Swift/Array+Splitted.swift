//
//  Array+Splitted.swift
//  Mendoza
//
//  Created by Tomas Camin on 26/01/2019.
//

import Foundation

extension Array {
    func split(in parts: Int) -> [[Element]] {
        var processedSize = 0

        return (0 ..< parts).map {
            let size = Int((Float(count - processedSize) / Float(parts - $0)).rounded())
            defer { processedSize += size }
            return Array(self[processedSize ..< processedSize + size])
        }
    }
}
