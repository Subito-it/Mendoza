import Foundation
import XCTest

extension Substring {
    func trimmed() -> Substring {
        guard let i = lastIndex(where: { $0 != " " }) else {
            return ""
        }
        return self[...i]
    }
}

extension String {
    public func trimmingLines() -> String {
        return split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmed() }
            .joined(separator: "\n")
    }
}
