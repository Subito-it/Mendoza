//
//  Operation+Extension.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

extension Operation {
    func addDependencies(_ ops: [Operation]) {
        ops.forEach { addDependency($0) }
    }
}
