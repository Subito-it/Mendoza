//
//  SimulatorService.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/08/2026.
//

import Foundation

/// A single simulator background service (launchd daemon) that can be disabled to
/// slim down a booted simulator. Each service maps to exactly one launchd label.
struct SimulatorService {
    let id: String
    let label: String
    let feature: String
}

/// A named group of services, offered as a convenience so callers can disable a
/// whole feature (e.g. `payments`) instead of naming each underlying service.
struct SimulatorServiceGroup {
    let id: String
    let feature: String
    let serviceIDs: [String]
}

/// Catalog of simulator background services and their groups, plus the pure logic
/// used to resolve user tokens into launchd labels and to compute the delta between
/// the observed disabled set and the desired one.
///
/// - Note: Disabling these via `launchctl disable` writes a persistent override into
///   the simulator's launchd database, so it survives reboots on iOS 18+. On iOS 17
///   and older the override is silently dropped on reboot.
enum SimulatorServiceCatalog {
    static let services: [SimulatorService] = [
        SimulatorService(id: "apsd", label: "com.apple.apsd", feature: "Push notifications"),
        SimulatorService(id: "storekitd", label: "com.apple.storekitd", feature: "StoreKit"),
        SimulatorService(id: "itunesstored", label: "com.apple.itunesstored", feature: "iTunes Store backend"),
        SimulatorService(id: "amsaccountsd", label: "com.apple.amsaccountsd", feature: "Apple Media Services accounts"),
        SimulatorService(id: "amsengagementd", label: "com.apple.amsengagementd", feature: "Apple Media Services engagement"),
        SimulatorService(id: "amsondevicestoraged", label: "com.apple.amsondevicestoraged", feature: "Apple Media Services on-device storage"),
        SimulatorService(id: "passd", label: "com.apple.passd", feature: "Wallet & passes"),
        SimulatorService(id: "financed", label: "com.apple.financed", feature: "Finance datastore"),
        SimulatorService(id: "appstored", label: "com.apple.appstored", feature: "App Store"),
        SimulatorService(id: "swcd", label: "com.apple.swcd", feature: "Universal links / associated domains"),
        SimulatorService(id: "searchd", label: "com.apple.searchd", feature: "Spotlight search"),
        SimulatorService(id: "searchtoold", label: "com.apple.searchtoold", feature: "Settings search"),
        SimulatorService(id: "assistantd", label: "com.apple.assistantd", feature: "Siri"),
        SimulatorService(id: "corespeechd", label: "com.apple.corespeechd", feature: "Speech recognition"),
        SimulatorService(id: "cloudd", label: "com.apple.cloudd", feature: "iCloud sync"),
        SimulatorService(id: "akd", label: "com.apple.akd", feature: "iCloud Keychain / Apple account auth"),
        SimulatorService(id: "contactsd", label: "com.apple.contactsd", feature: "Contacts"),
        SimulatorService(id: "calaccessd", label: "com.apple.calaccessd", feature: "Calendar"),
        SimulatorService(id: "remindd", label: "com.apple.remindd", feature: "Reminders"),
        SimulatorService(id: "maild", label: "com.apple.email.maild", feature: "Mail"),
        SimulatorService(id: "assetsd", label: "com.apple.assetsd", feature: "Photos library"),
        SimulatorService(id: "photoanalysisd", label: "com.apple.photoanalysisd", feature: "Photos analysis"),
        SimulatorService(id: "healthd", label: "com.apple.healthd", feature: "HealthKit"),
        SimulatorService(id: "homed", label: "com.apple.homed", feature: "HomeKit"),
        SimulatorService(id: "identityservicesd", label: "com.apple.identityservicesd", feature: "iMessage & FaceTime"),
        SimulatorService(id: "chronod", label: "com.apple.chronod", feature: "Widgets"),
        SimulatorService(id: "liveactivitiesd", label: "com.apple.liveactivitiesd", feature: "Live Activities"),
        SimulatorService(id: "mapssyncd", label: "com.apple.Maps.mapssyncd", feature: "Maps background sync"),
        SimulatorService(id: "weatherd", label: "com.apple.weatherd", feature: "Weather"),
        SimulatorService(id: "newsd", label: "com.apple.newsd", feature: "News"),
        SimulatorService(id: "gamed", label: "com.apple.gamed", feature: "Game Center"),
        SimulatorService(id: "findmylocated", label: "com.apple.findmy.findmylocated", feature: "Find My"),
        SimulatorService(id: "screentimeagent", label: "com.apple.ScreenTimeAgent", feature: "Screen Time"),
    ]

    static let groups: [SimulatorServiceGroup] = [
        SimulatorServiceGroup(id: "payments", feature: "StoreKit / in-app purchase", serviceIDs: [
            "storekitd", "itunesstored", "amsaccountsd", "amsengagementd", "amsondevicestoraged", "passd", "financed",
        ]),
        SimulatorServiceGroup(id: "app-store", feature: "App Store", serviceIDs: ["appstored", "itunesstored"]),
        SimulatorServiceGroup(id: "spotlight", feature: "Spotlight & Settings search", serviceIDs: ["searchd", "searchtoold"]),
        SimulatorServiceGroup(id: "siri", feature: "Siri & speech", serviceIDs: ["assistantd", "corespeechd"]),
        SimulatorServiceGroup(id: "photos", feature: "Photos library & analysis", serviceIDs: ["assetsd", "photoanalysisd"]),
        SimulatorServiceGroup(id: "widgets", feature: "Widgets & Live Activities", serviceIDs: ["chronod", "liveactivitiesd"]),
    ]

    /// The complete set of labels Mendoza is allowed to disable or enable. Any label
    /// outside this allowlist is never touched, in either direction.
    static let managed: Set<String> = Set(services.map(\.label))

    private static let servicesByID: [String: SimulatorService] = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
    private static let groupsByID: [String: SimulatorServiceGroup] = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

    /// Resolves a list of user tokens (group ids and/or service ids, in one flat
    /// namespace) into the union of their launchd labels. Throws on any unknown token.
    static func resolveLabels(for tokens: [String]) throws -> Set<String> {
        var labels = Set<String>()

        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let group = groupsByID[trimmed] {
                for serviceID in group.serviceIDs {
                    guard let service = servicesByID[serviceID] else {
                        throw Error("Group '\(group.id)' references unknown service '\(serviceID)'")
                    }
                    labels.insert(service.label)
                }
            } else if let service = servicesByID[trimmed] {
                labels.insert(service.label)
            } else {
                throw Error("Unknown simulator service or group '\(trimmed)'. \(helpDescription)")
            }
        }

        return labels
    }

    /// Human readable list of the tokens accepted by `resolveLabels`, for the CLI help.
    static var helpDescription: String {
        let groupIDs = groups.map(\.id).sorted().joined(separator: ", ")
        let serviceIDs = services.map(\.id).sorted().joined(separator: ", ")
        return "Groups: \(groupIDs). Services: \(serviceIDs)"
    }
}

/// Computes the transitions needed to move a simulator from its currently disabled
/// set to the desired one, scoped to the managed allowlist in both directions.
///
/// - Parameters:
///   - current: labels currently disabled on the device (as read from launchd).
///   - desired: labels that should end up disabled.
/// - Returns: labels to disable (want off, is on) and to enable (is off, want on),
///   both filtered to the managed allowlist and sorted for determinism.
func serviceDelta(current: Set<String>, desired: Set<String>) -> (toDisable: [String], toEnable: [String]) {
    let managed = SimulatorServiceCatalog.managed
    let toDisable = desired.intersection(managed).subtracting(current).sorted()
    let toEnable = current.intersection(managed).subtracting(desired).sorted()
    return (toDisable: toDisable, toEnable: toEnable)
}
