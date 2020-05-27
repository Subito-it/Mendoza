//
//  TestFilters.swift
//  Mendoza
//
//  Created by Ashraf Ali on 26/05/2020.
//

import Foundation

public struct TestFilters: Codable {
    let include: [String]
    let exclude: [String]

    public init(commaSeparatedIncludePattern: String?, commaSeparatedExcludePattern: String?) {
        let patterns: (String?) -> [String]? = { pattern in
            guard let pattern = pattern else {
                return nil
            }

            let patterns = pattern.components(separatedBy: ",").map { $0.lowercased() }
            return Array(Set(patterns))
        }

        include = patterns(commaSeparatedIncludePattern) ?? []
        exclude = patterns(commaSeparatedExcludePattern) ?? []
    }
}
