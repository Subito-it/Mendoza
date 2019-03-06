//
//  Bariloche+Extension.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/01/2019.
//

import Foundation
import Bariloche

extension Bariloche {
    static func ask<T: CustomStringConvertible>(title: String, array: [T]) -> (value: T, index: Int) {
        var question = ["", title.underline]
        for (index, item) in array.enumerated() {
            question.append("\(index + 1)) \(item.description)")
        }
        
        let selectedIndex: Int = ask(question.joined(separator: "\n")) { answer in
            guard 1...array.count ~= answer else { throw Error("Invalid index") }
            return answer - 1
        }
        
        return (array[selectedIndex], selectedIndex)
    }
}
