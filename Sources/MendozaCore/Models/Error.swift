//
//  Error.swift
//  Mendoza
//
//  Created by Tomas Camin on 08/01/2019.
//

import Foundation

public struct Error: LocalizedError {
    public var errorDescription: String? { return description }
    public let didLogError: Bool

    private let description: String

    public init(_ description: String, logger: ExecuterLogger? = nil) {
        self.description = description
        didLogError = (logger != nil)
        logger?.log(exception: description)
    }
}
