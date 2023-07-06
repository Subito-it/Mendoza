//
//  String+Extension.swift
//  Mendoza
//
//  Created by Tomas Camin on 01/02/2019.
//

import Foundation

extension String {
    private static var lock = NSLock()
    private static var regexCache = [String: NSRegularExpression]()

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
        var regex: NSRegularExpression!

        Self.lock.lock()
        regex = Self.regexCache[pattern]
        Self.lock.unlock()

        if regex == nil {
            regex = try NSRegularExpression(pattern: pattern, options: [])

            Self.lock.lock()
            Self.regexCache[pattern] = regex
            Self.lock.unlock()
        }

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
