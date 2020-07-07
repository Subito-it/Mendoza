public struct TestSummary {
    let testsCount: String
    let failuresCount: String
    let unexpectedCount: String
    let time: String
    let colored: Bool
}

extension TestSummary {
    func isSuccess() -> Bool {
        guard let failures = Int(failuresCount) else { return false }
        return failures == 0
    }

    var description: String {
        return "\(failuresCount) failed, \(testsCount) total (\(time) seconds)"
    }

    public func format() -> String {
        if isSuccess() {
            return colored ? "Tests Passed: \(description)".bold.green : "Tests Passed: \(description)"
        } else {
            return colored ? "Tests Failed: \(description)".bold.red : "Tests Failed: \(description)"
        }
    }
}
