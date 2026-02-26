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
        self.description = Self.truncate(description)
        self.didLogError = (logger != nil)
        logger?.log(exception: description)
    }

    private static func truncate(_ text: String) -> String {
        let truncateSize = 8_192
        let head = String(text.prefix(truncateSize))
        let tail = String(text.suffix(min(truncateSize, max(0, text.count - truncateSize))))

        if tail.count > 0 {
            return head + "\n\n\n <truncated> \n\n\n" + tail
        } else {
            return head
        }
    }
}

/// Error thrown when no test cases are found to execute.
/// This is not a failure condition - it allows early termination of the pipeline.
struct NoTestCasesFoundError: LocalizedError {
    var errorDescription: String? { "No test cases found to execute" }
}
