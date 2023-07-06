//
//  TestRunner.swift
//  Mendoza
//
//  Created by Tomas Camin on 21/03/2019.
//

import Foundation

protocol TestRunner {
    var id: String { get }
    var name: String { get }
}

extension Simulator: TestRunner {}

extension Node: TestRunner {
    var id: String { address }
}
