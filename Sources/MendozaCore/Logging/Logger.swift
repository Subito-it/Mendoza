//
//  Logger.swift
//  Mendoza
//
//  Created by Tomas Camin on 04/02/2019.
//

import Foundation

protocol Logger: AnyObject, Hashable, CustomStringConvertible {
    var filename: String { get }
    var hasErrors: Bool { get }
    var isEmpty: Bool { get }
    var dumpToStandardOutput: Bool { get set }

    func log(command: String)
    func log(output: String, statusCode: Int32)
    func log(exception: String)

    func addBlackList(_ word: String)

    func redact(_ input: String) -> String

    func dump() throws
}
