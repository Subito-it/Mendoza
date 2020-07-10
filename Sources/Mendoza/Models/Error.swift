//
//  Error.swift
//  Mendoza
//
//  Created by Tomas Camin on 08/01/2019.
//

import Foundation

struct Error: LocalizedError {
    var errorDescription: String? { description }
    let didLogError: Bool

    private let description: String

    init(_ description: String, logger: ExecuterLogger? = nil) {
        self.description = description
        didLogError = (logger != nil)
        logger?.log(exception: description)
    }
}
