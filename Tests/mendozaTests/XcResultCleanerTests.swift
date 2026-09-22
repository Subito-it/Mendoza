import CachiKit
import Foundation
@testable import mendoza
import XCTest

final class XcResultCleanerTests: XCTestCase {
    private func typed(_ name: String, _ fields: [String: Any] = [:]) -> [String: Any] {
        fields.merging(["_type": ["_name": name]]) { _, value in value }
    }

    private func string(_ value: String) -> [String: Any] {
        typed("String", ["_value": value])
    }

    private func array(_ values: [[String: Any]]) -> [String: Any] {
        typed("Array", ["_values": values])
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(type, from: data)
    }

    func testCachiKitDecodesOldAndXcode27EmptyArrays() throws {
        for empty in [array([]), typed("Array")] {
            let object: [String: Any] = ["metrics": [:], "issues": ["analyzerWarningSummaries": empty], "actions": empty]
            let decoded = try decode(ActionsInvocationRecord.self, from: object)
            XCTAssertTrue(decoded.actions.isEmpty)
            XCTAssertEqual(decoded.issues?.analyzerWarningSummaries?.count, 0)
        }
    }

    func testCachiKitDoesNotHideMalformedValuesOrMissingRequiredData() throws {
        for invalid in [typed("Array", ["_values": "invalid"]), typed("Array", ["_values": NSNull()])] {
            let object: [String: Any] = ["metrics": [:], "issues": [:], "actions": invalid]
            XCTAssertThrowsError(try decode(ActionsInvocationRecord.self, from: object))
        }
        XCTAssertThrowsError(try decode(ActionsInvocationRecord.self, from: ["issues": [:], "actions": array([])]))
    }

    private func plan(_ targets: [[String]]) -> [String: Any] {
        let testables = targets.map { tests in
            let metadata = tests.map { id in
                typed("ActionTestMetadata", ["name": string(id), "identifier": string(id), "testStatus": string("Success"), "summaryRef": ["id": string(id)]])
            }
            let group = typed("ActionTestSummaryGroup", ["name": string("ExampleTests"), "identifier": string("ExampleTests"), "subtests": array(metadata)])
            return typed("ActionTestableSummary", ["name": string("ExampleUITests"), "tests": array([group])])
        }
        return typed("ActionTestPlanRunSummary", ["name": string("ExamplePlan"), "testableSummaries": array(testables)])
    }

    private func summary(_ id: String) -> [String: Any] {
        func attachment(_ suffix: String) -> [String: Any] {
            typed("ActionTestAttachment", ["uniformTypeIdentifier": string("public.png"), "lifetime": string("keepAlways"), "payloadRef": ["id": string(id + suffix)]])
        }
        let nested = typed("ActionTestActivitySummary", ["activityType": string("test"), "uuid": string("nested"), "attachments": array([attachment("-nested")])])
        let activity = typed("ActionTestActivitySummary", ["activityType": string("test"), "uuid": string("activity"), "attachments": array([attachment("-image")]), "subactivities": array([nested])])
        let failure = typed("ActionTestFailureSummary", ["attachments": array([attachment("-failure")])])
        return ["name": string(id), "identifier": string(id), "testStatus": string("Success"), "performanceMetrics": typed("Array"), "activitySummaries": array([activity]), "failureSummaries": array([failure])]
    }

    func testOneCleanerProtectsSingleAndMultipleTestsAcrossPlansAndTargets() throws {
        let scenarios: [[[String: Any]]] = [[plan([["a"]])], [plan([["a", "b"], ["c"]]), plan([["d"]])]]
        for plans in scenarios {
            var requested = Set<String>()
            let cleaner = XcResultCleaner(path: "/tmp/example.xcresult", readObject: { identifier -> Data in
                let id = try XCTUnwrap(identifier)
                requested.insert(id)
                let object: [String: Any]
                if id == "plans" {
                    object = ["summaries": self.array(plans)]
                } else {
                    object = self.summary(id)
                }
                return try JSONSerialization.data(withJSONObject: object)
            })
            let protected = try Set(cleaner.protectedTestIdentifiers(for: "plans"))
            let tests = plans.count == 1 ? ["a"] : ["a", "b", "c", "d"]
            XCTAssertEqual(requested, Set(tests + ["plans"]))
            for id in tests {
                for suffix in ["", "-image", "-nested", "-failure"] {
                    XCTAssertTrue(protected.contains(id + suffix))
                }
            }
        }
    }

    func testMissingMemberSummaryFailsCleanupInsteadOfIgnoringItsAttachments() throws {
        let cleaner = XcResultCleaner(path: "/tmp/example.xcresult", readObject: { id in
            if id == "b" {
                throw NSError(domain: "fixture", code: 1)
            }
            let object = id == "plans" ? ["summaries": self.array([self.plan([["a", "b"]])])] : self.summary("a")
            return try JSONSerialization.data(withJSONObject: object)
        })
        XCTAssertThrowsError(try cleaner.protectedTestIdentifiers(for: "plans"))
    }

    func testNoTestSummariesPreservesLargeBlobs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dataDirectory = directory.appendingPathComponent("Data")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blob = dataDirectory.appendingPathComponent("blob")
        let data = Data(repeating: 42, count: 4_096)
        try data.write(to: blob)
        let root: [String: Any] = ["metrics": [:], "issues": [:], "actions": typed("Array")]
        let cleaner = XcResultCleaner(path: directory.path, readObject: { _ in try JSONSerialization.data(withJSONObject: root) })
        XCTAssertThrowsError(try cleaner.clean(minimumSizeKB: 2))
        XCTAssertEqual(try Data(contentsOf: blob), data)
    }
}
