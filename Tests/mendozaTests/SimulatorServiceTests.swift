@testable import mendoza
import XCTest

final class SimulatorServiceTests: XCTestCase {
    /// Daemons that wedge or deadlock a simulator when disabled. None must ever
    /// appear in the catalog; nanoregistryd in particular hangs every subsequent
    /// simctl call, which would mean a hung node with no useful error.
    ///
    /// `nanoregistrylaunchd` used to be listed here by association with nanoregistryd,
    /// but disabling it on its own was measured to be safe (simctl stayed responsive
    /// across a reboot) and is what keeps the Watch companion daemons down, so it is now
    /// in the catalog instead.
    private let forbiddenLabels: Set<String> = [
        "com.apple.nanoregistryd",
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
            "com.apple.financed",
            "com.apple.merchantd"
        ])
    }

    func testResolveSiriGroupCoversTheWholeSubsystem() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["siri"])
        XCTAssertEqual(labels, [
            "com.apple.assistantd",
            "com.apple.corespeechd",
            "com.apple.siriinferenced",
            "com.apple.siriknowledged",
            "com.apple.siriactionsd",
            "com.apple.sirittsd",
            "com.apple.siri.context.service",
            "com.apple.siri.acousticsignature"
        ])
    }

    func testResolveIntelligenceGroup() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["intelligence"])
        XCTAssertEqual(labels, [
            "com.apple.intelligenceplatformd",
            "com.apple.intelligencetasksd",
            "com.apple.intelligenceflowd",
            "com.apple.intelligencecontextd",
            "com.apple.callintelligenced",
            "com.apple.fitnessintelligenced",
            "com.apple.suggestd"
        ])
    }

    func testResolvePostersGroup() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["posters"])
        XCTAssertEqual(labels, ["com.apple.PosterBoard", "com.apple.contacts.postersyncd"])
    }

    func testResolveGenerativeGroup() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["generative"])
        XCTAssertEqual(labels.count, 14)
        XCTAssertTrue(labels.contains("com.apple.generativeexperiencesd"))
        XCTAssertTrue(labels.contains("com.apple.imageplaygroundd"))
        XCTAssertTrue(labels.contains("com.apple.modelcatalogd"))
        XCTAssertTrue(labels.contains("com.apple.translationd"))
        XCTAssertTrue(labels.contains("com.apple.mlhostd"))
        XCTAssertTrue(labels.contains("com.apple.GenerativeFunctions.agentstored"))
    }

    func testResolveWatchGroup() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["watch"])
        XCTAssertEqual(labels.count, 14)
        // Without the enabler the rest of the group is re-enabled ~15s into every boot, so
        // the delta never converges and each run pays an extra reboot.
        XCTAssertTrue(labels.contains("com.apple.nanoregistrylaunchd"))
        XCTAssertTrue(labels.contains("com.apple.nanomapscd"))
        XCTAssertTrue(labels.contains("com.apple.nanosystemsettingsd"))
        XCTAssertTrue(labels.contains("com.apple.NPKCompanionAgent"))
        XCTAssertTrue(labels.contains("com.apple.companionappd"))
        XCTAssertTrue(labels.contains("com.apple.brook.brookcompaniond"))
    }

    func testResolveIsUnionAndOrderIndependent() throws {
        let a = try SimulatorServiceCatalog.resolveLabels(for: ["payments", "app-store"])
        let b = try SimulatorServiceCatalog.resolveLabels(for: ["app-store", "payments"])
        XCTAssertEqual(a, b)
        // payments (8) ∪ app-store (appstored, itunesstored) — itunesstored is shared
        XCTAssertEqual(a.count, 9)
    }

    func testResolveGroupAndOverlappingServiceDoNotDoubleCount() throws {
        let labels = try SimulatorServiceCatalog.resolveLabels(for: ["payments", "passd"])
        XCTAssertEqual(labels.count, 8)
    }

    func testResolveEmptyAndWhitespaceTokensIgnored() throws {
        XCTAssertEqual(try SimulatorServiceCatalog.resolveLabels(for: ["", "  ", "apsd"]), ["com.apple.apsd"])
    }

    func testResolveUnknownTokenThrows() {
        XCTAssertThrowsError(try SimulatorServiceCatalog.resolveLabels(for: ["nope"]))
    }

    func testDeltaStockToDesiredDisablesRequested() {
        let delta = SimulatorServiceCatalog.delta(current: [], desired: ["com.apple.apsd", "com.apple.assistantd"])
        XCTAssertEqual(delta.toDisable, ["com.apple.apsd", "com.apple.assistantd"])
        XCTAssertEqual(delta.toEnable, [])
    }

    func testDeltaReenablesManagedLabelNoLongerDesired() {
        let delta = SimulatorServiceCatalog.delta(current: ["com.apple.apsd", "com.apple.assistantd"], desired: ["com.apple.apsd"])
        XCTAssertEqual(delta.toDisable, [])
        XCTAssertEqual(delta.toEnable, ["com.apple.assistantd"])
    }

    func testDeltaNoOpWhenConverged() {
        let delta = SimulatorServiceCatalog.delta(current: ["com.apple.apsd"], desired: ["com.apple.apsd"])
        XCTAssertEqual(delta.toDisable, [])
        XCTAssertEqual(delta.toEnable, [])
        XCTAssertTrue(delta.isEmpty)
    }

    func testDeltaIsNotEmptyWhenATransitionIsNeeded() {
        XCTAssertFalse(SimulatorServiceCatalog.delta(current: [], desired: ["com.apple.apsd"]).isEmpty)
        XCTAssertFalse(SimulatorServiceCatalog.delta(current: ["com.apple.apsd"], desired: []).isEmpty)
    }

    func testDeltaIgnoresUnmanagedLabelsBothDirections() {
        // An unmanaged label that is disabled must not be re-enabled, and an
        // unmanaged desired label must not be disabled.
        let delta = SimulatorServiceCatalog.delta(current: ["com.apple.somethingelse"], desired: ["com.apple.anotherunmanaged"])
        XCTAssertEqual(delta.toDisable, [])
        XCTAssertEqual(delta.toEnable, [])
    }

    func testParseDisabledServicesIgnoresEnabledOverridesAndNoise() {
        // Verbatim shape of `launchctl print-disabled system`, which reports both directions.
        let output = """
        \tdisabled services = {
        \t\t"com.apple.apsd" => disabled
        \t\t"com.apple.pairedsyncd" => enabled
        \t\t"com.apple.oldstyledisabled" => true
        \t\t"com.apple.oldstyleenabled" => false
        \t}
        Could not print cache: 141: Reentrancy avoided
        """

        XCTAssertEqual(CommandLineProxy.Simulators.parseDisabledServices(output),
                       ["com.apple.apsd", "com.apple.oldstyledisabled"])
    }
}
