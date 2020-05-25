//
//  TestFilters.swift
//  Mendoza
//
//  Created by Ashraf Ali on 26/05/2020.
//

import Foundation

struct TestFilters: Codable {
    let include: [String]
    let exclude: [String]

    init(commaSeparatedIncludePattern: String?, commaSeparatedExcludePattern: String?) {
        let patterns: (String?) -> [String]? = { pattern in
            guard let pattern = pattern else {
                return nil
            }

            let patterns = pattern.components(separatedBy: ",")
            return Array(Set(patterns))
        }

        include = patterns(commaSeparatedIncludePattern) ?? []
        exclude = patterns(commaSeparatedExcludePattern) ?? []
    }
}
