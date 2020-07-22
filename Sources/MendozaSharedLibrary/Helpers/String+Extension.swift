//
//  String+Extension.swift
//  Mendoza
//
//  Created by Tomas Camin on 01/02/2019.
//

import Foundation

public extension String {
    func capturedGroups(regex: NSRegularExpression) -> [String] {
        var results = [String]()

        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: count))

        guard let match = matches.first else { return results }

        let lastRangeIndex = match.numberOfRanges - 1
        guard lastRangeIndex >= 1 else { return results }

        for i in 1 ... lastRangeIndex {
            let location = match.range(at: i)
            guard location.location != NSNotFound else {
                results.append("")
                continue
            }

            let sIndex = index(startIndex, offsetBy: location.location)
            let eIndex = index(sIndex, offsetBy: location.length)

            results.append(String(self[sIndex ..< eIndex]))
        }

        return results
    }

    func capturedGroups(withRegexString pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern, options: [])

        return capturedGroups(regex: regex)
    }

    func expandingTilde() -> String {
        if #available(OSX 10.12, *) {
            return replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        } else {
            return replacingOccurrences(of: "~", with: NSHomeDirectory())
        }
    }
}

public extension String {
    var toDictionary: [String: String] {
        return Dictionary(uniqueKeysWithValues: components(separatedBy: ",").map { $0.components(separatedBy: ":") }.compactMap { ($0[0], $0[1]) })
    }

    var boolValue: Bool {
        return (self as NSString).boolValue
    }
}
