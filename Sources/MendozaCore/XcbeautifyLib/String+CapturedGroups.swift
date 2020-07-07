import Foundation

extension String {
    func capturedGroups(with pattern: Pattern) -> [String] {
        var results = [String]()

        var regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern.rawValue, options: [.caseInsensitive])
        } catch {
            return results
        }

        let matches = regex.matches(in: self, range: NSRange(location: 0, length: utf16.count))

        guard let match = matches.first else { return results }

        let lastRangeIndex = match.numberOfRanges - 1
        guard lastRangeIndex >= 1 else { return results }

        for i in 1 ... lastRangeIndex {
            let capturedGroupIndex = match.range(at: i)
            guard let matchedString = substring(with: capturedGroupIndex) else { continue }
            results.append(matchedString)
        }

        return results
    }

    /**
     Returns a `[[String:String]]` of all matches of a `NSRegularExpression` against a `String`.

     - parameter String: the regular expression
     - returns: an `[[String:String]]`, where every element represents a distinct match of the entire regular expression against `s`.

     In the return value, every element represents a distinct match of the entire regular expression against the string. Every element is itself a `Dictionary<String,Substring?>`,
     mapping the name of the capture groups to the Substring which matched that capture group.

     So for example, a match on the regular expression "a(?<middleChar.)z" includes one capture group named "middleChar".
     It would match three times against against the string "aaz abz acz". This would be expressed as the array [["middleChar":"a"], ["middleChar":"b"], ["middleChar":"c"]]

     */

    func capturedNamedGroups(with pattern: Pattern) -> [String: String] {
        var results = [String: String]()

        var regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern.rawValue, options: [.caseInsensitive])
        } catch {
            return results
        }

        let names = namedCaptureGroups(regularExpression: regex)

        let matches = regex.matches(in: self, options: [], range: NSRange(startIndex ..< endIndex, in: self))

        let output = matches.flatMap { match -> [String: String] in
            let keyvalues = names.enumerated().map { (index, name: String) -> (String, String) in
                let captureGroupRange: NSRange
                if #available(OSX 10.13, *) {
                    captureGroupRange = match.range(withName: name)
                } else {
                    captureGroupRange = match.range(at: index)
                }

                guard captureGroupRange.location != NSNotFound else {
                    return (name, "")
                }

                return (name, self[Range(captureGroupRange, in: self)!].description)
            }

            return Dictionary(uniqueKeysWithValues: keyvalues)
        }

        results = Dictionary(output, uniquingKeysWith: { first, _ in first })

        return results
    }

    /// Returns the names of capture groups in the regular expression.
    private func namedCaptureGroups(regularExpression: NSRegularExpression) -> [String] {
        var results = [String]()
        var regex: NSRegularExpression

        do {
            regex = try NSRegularExpression(pattern: "\\(\\?\\<(\\w+)\\>", options: [.caseInsensitive])
        } catch {
            return results
        }

        let regexString = regularExpression.pattern
        let matches = regex.matches(in: regexString, options: [], range: NSRange(regexString.startIndex ..< regexString.endIndex, in: regexString))

        results = matches.map { match -> String in
            (regexString as NSString).substring(with: match.range(at: 1))
        }

        return results
    }
}
