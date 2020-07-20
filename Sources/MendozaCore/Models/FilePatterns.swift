//
//  FilePatterns.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/01/2019.
//

import Foundation

public struct FilePatterns: Codable {
    let include: [String]
    let exclude: [String]

    public init(commaSeparatedIncludePattern: String?, commaSeparatedExcludePattern: String?) {
        let patterns: (String?) -> [String]? = { pattern in
            guard let pattern = pattern else { return nil }

            let patterns = pattern.components(separatedBy: ",")
            // Clunky way to support, both regex and wildcard styles
            return Array(Set(patterns + patterns.map { $0.replacingOccurrences(of: "*.", with: #"(.*)\."#) }))
        }
        include = patterns(commaSeparatedIncludePattern) ?? [#"\.(m|swift)$"#]
        exclude = patterns(commaSeparatedExcludePattern) ?? [""]
    }
}
