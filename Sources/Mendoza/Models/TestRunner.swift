//
//  TestRunner.swift
//  Mendoza
//
//  Created by tomas on 21/03/2019.
//

import Foundation

protocol TestRunner {
    var id: String { get }
    var name: String { get }
}

extension Simulator: TestRunner {}

extension Node: TestRunner {
    var id: String { return address }
}
