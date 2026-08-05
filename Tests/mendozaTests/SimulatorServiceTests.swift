@testable import mendoza
import XCTest

final class SimulatorServiceTests: XCTestCase {
    /// Daemons that wedge or deadlock a simulator when disabled. None must ever
    /// appear in the catalog; nanoregistryd in particular hangs every subsequent
    /// simctl call, which would mean a hung node with no useful error.
    private let forbiddenLabels: Set<String> = [
        "com.apple.nanoregistryd",
        "com.apple.nanoregistrylaunchd",
        "com.apple.nanoprefsyncd.2",
        "com.apple.nanotimekitcompaniond",
        "com.apple.nanobackupd",
        "com.apple.sleepd",
        "com.apple.appprotectiond",
        "com.apple.ManagedSettingsAgent",
        "com.apple.managedconfiguration.profiled",
        "com.apple.mobiletimerd",
        "com.apple.routined",
        "com.apple.biomed",
        "com.apple.biomesyncd",
        "com.apple.dmd",
        "com.apple.donotdisturbd"
    ]

    func testEveryLabelMatchesExpectedFormat() throws {
        // Labels are interpolated into shell commands, so they must be well-formed.
        let regex = try NSRegularExpression(pattern: #"^com\.apple\.[A-Za-z0-9._-]+$"#)
        for service in SimulatorServiceCatalog.services {
            let range = NSRange(service.label.startIndex..., in: service.label)
            XCTAssertNotNil(regex.firstMatch(in: service.label, range: range), "Malformed label: \(service.label)")
        }
    }

    func testNoDuplicateServiceIDs() {
        let ids = SimulatorServiceCatalog.services.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate service ids")
    }

    func testNoDuplicateLabels() {
        let labels = SimulatorServiceCatalog.services.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count, "Duplicate labels — one-service-per-process violated")
    }

    func testNoDuplicateGroupIDs() {
        let ids = SimulatorServiceCatalog.groups.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate group ids")
    }

    func testGroupAndServiceNamespacesDoNotCollide() {
        let serviceIDs = Set(SimulatorServiceCatalog.services.map(\.id))
        let groupIDs = Set(SimulatorServiceCatalog.groups.map(\.id))
        XCTAssertTrue(serviceIDs.isDisjoint(with: groupIDs), "A group id collides with a service id")
    }

    func testNoForbiddenLabelInCatalog() {
        for service in SimulatorServiceCatalog.services {
            XCTAssertFalse(forbiddenLabels.contains(service.label), "Forbidden label present: \(service.label)")
        }
    }

    func testEveryGroupServiceIDResolvesToARealService() {
        let serviceIDs = Set(SimulatorServiceCatalog.services.map(\.id))
        for group in SimulatorServiceCatalog.groups {
            for serviceID in group.serviceIDs {
                XCTAssertTrue(serviceIDs.contains(serviceID), "Group '\(group.id)' references unknown service '\(serviceID)'")
            }
        }
    }

    func testManagedIsUnionOfAllServiceLabels() {
        XCTAssertEqual(SimulatorServiceCatalog.managed, Set(SimulatorServiceCatalog.services.map(\.label)))
    }

    func testResolveSingleService() throws {
        XCTAssertEqual(try SimulatorServiceCatalog.resolveLabels(for: ["apsd"]), ["com.apple.apsd"])
    }

    func testResolveGroupExpandsToAllLabels() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["payments"])
        XCTAssertEqual(labels, [
            "com.apple.storekitd",
            "com.apple.itunesstored",
            "com.apple.amsaccountsd",
            "com.apple.amsengagementd",
            "com.apple.amsondevicestoraged",
            "com.apple.passd",
            "com.apple.financed"
        ])
    }

    func testResolveIsUnionAndOrderIndependent() throws {
        let a = try SimulatorServiceCatalog.resolveLabels(for: ["payments", "app-store"])
        let b = try SimulatorServiceCatalog.resolveLabels(for: ["app-store", "payments"])
        XCTAssertEqual(a, b)
        // payments (7) ∪ app-store (appstored, itunesstored) — itunesstored is shared
        XCTAssertEqual(a.count, 8)
    }

    func testResolveGroupAndOverlappingServiceDoNotDoubleCount() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["payments", "passd"])
        XCTAssertEqual(labels.count, 7)
    }

    func testResolveEmptyAndWhitespaceTokensIgnored() throws {
        XCTAssertEqual(try SimulatorServiceCatalog.resolveLabels(for: ["", "  ", "apsd"]), ["com.apple.apsd"])
    }

    func testResolveUnknownTokenThrows() {
        XCTAssertThrowsError(try SimulatorServiceCatalog.resolveLabels(for: ["nope"]))
    }

    func testDeltaStockToDesiredDisablesRequested() {
        let delta = serviceDelta(current: [], desired: ["com.apple.apsd", "com.apple.assistantd"])
        XCTAssertEqual(delta.toDisable, ["com.apple.apsd", "com.apple.assistantd"])
        XCTAssertEqual(delta.toEnable, [])
    }

    func testDeltaReenablesManagedLabelNoLongerDesired() {
        let delta = serviceDelta(current: ["com.apple.apsd", "com.apple.assistantd"], desired: ["com.apple.apsd"])
        XCTAssertEqual(delta.toDisable, [])
        XCTAssertEqual(delta.toEnable, ["com.apple.assistantd"])
    }

    func testDeltaNoOpWhenConverged() {
        let delta = serviceDelta(current: ["com.apple.apsd"], desired: ["com.apple.apsd"])
        XCTAssertEqual(delta.toDisable, [])
        XCTAssertEqual(delta.toEnable, [])
    }

    func testDeltaIgnoresUnmanagedLabelsBothDirections() {
        // An unmanaged label that is disabled must not be re-enabled, and an
        // unmanaged desired label must not be disabled.
        let delta = serviceDelta(current: ["com.apple.somethingelse"], desired: ["com.apple.anotherunmanaged"])
        XCTAssertEqual(delta.toDisable, [])
        XCTAssertEqual(delta.toEnable, [])
    }
}
