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
        // Push & notifications
        SimulatorService(id: "apsd", label: "com.apple.apsd", feature: "Push notifications"),

        // StoreKit & payments
        SimulatorService(id: "storekitd", label: "com.apple.storekitd", feature: "StoreKit"),
        SimulatorService(id: "itunesstored", label: "com.apple.itunesstored", feature: "iTunes Store backend"),
        SimulatorService(id: "amsaccountsd", label: "com.apple.amsaccountsd", feature: "Apple Media Services accounts"),
        SimulatorService(id: "amsengagementd", label: "com.apple.amsengagementd", feature: "Apple Media Services engagement"),
        SimulatorService(id: "amsondevicestoraged", label: "com.apple.amsondevicestoraged", feature: "Apple Media Services on-device storage"),
        SimulatorService(id: "passd", label: "com.apple.passd", feature: "Wallet & passes"),
        SimulatorService(id: "financed", label: "com.apple.financed", feature: "Finance datastore"),
        SimulatorService(id: "merchantd", label: "com.apple.merchantd", feature: "Apple Pay merchant"),
        SimulatorService(id: "appstored", label: "com.apple.appstored", feature: "App Store"),
        SimulatorService(id: "itunescloudd", label: "com.apple.itunescloudd", feature: "iTunes Cloud sync"),

        // Links & sharing
        SimulatorService(id: "swcd", label: "com.apple.swcd", feature: "Universal links / associated domains"),
        SimulatorService(id: "sharingd", label: "com.apple.sharingd", feature: "AirDrop & proximity sharing"),

        // Spotlight & search
        SimulatorService(id: "searchd", label: "com.apple.searchd", feature: "Spotlight search"),
        SimulatorService(id: "searchtoold", label: "com.apple.searchtoold", feature: "Settings search"),
        SimulatorService(id: "spotlightknowledgedupdater", label: "com.apple.spotlightknowledged.updater", feature: "Spotlight knowledge updater"),
        SimulatorService(id: "parsecd", label: "com.apple.parsecd", feature: "Parsec search ranking"),

        // Siri & speech
        SimulatorService(id: "assistantd", label: "com.apple.assistantd", feature: "Siri"),
        SimulatorService(id: "corespeechd", label: "com.apple.corespeechd", feature: "Speech recognition"),
        SimulatorService(id: "siriinferenced", label: "com.apple.siriinferenced", feature: "Siri inference"),
        SimulatorService(id: "siriknowledged", label: "com.apple.siriknowledged", feature: "Siri knowledge"),
        SimulatorService(id: "siriactionsd", label: "com.apple.siriactionsd", feature: "Siri actions"),
        SimulatorService(id: "sirittsd", label: "com.apple.sirittsd", feature: "Siri text to speech"),
        SimulatorService(id: "siricontextd", label: "com.apple.siri.context.service", feature: "Siri context"),
        SimulatorService(id: "siriacousticsignatured", label: "com.apple.siri.acousticsignature", feature: "Siri acoustic signature"),

        // iCloud, contacts, calendar, mail
        SimulatorService(id: "cloudd", label: "com.apple.cloudd", feature: "iCloud sync"),
        SimulatorService(id: "akd", label: "com.apple.akd", feature: "iCloud Keychain / Apple account auth"),
        SimulatorService(id: "contactsd", label: "com.apple.contactsd", feature: "Contacts"),
        SimulatorService(id: "calaccessd", label: "com.apple.calaccessd", feature: "Calendar"),
        SimulatorService(id: "remindd", label: "com.apple.remindd", feature: "Reminders"),
        SimulatorService(id: "maild", label: "com.apple.email.maild", feature: "Mail"),
        SimulatorService(id: "icloudmailagent", label: "com.apple.icloudmailagent", feature: "iCloud Mail sync"),
        SimulatorService(id: "dataaccessd", label: "com.apple.dataaccess.dataaccessd", feature: "Exchange & data access"),
        SimulatorService(id: "addressbooksyncd", label: "com.apple.addressbooksyncd", feature: "Address book sync"),
        SimulatorService(id: "peopled", label: "com.apple.peopled", feature: "People suggestions"),

        // Photos
        SimulatorService(id: "assetsd", label: "com.apple.assetsd", feature: "Photos library"),
        SimulatorService(id: "photoanalysisd", label: "com.apple.photoanalysisd", feature: "Photos analysis"),
        SimulatorService(id: "mediaanalysisd", label: "com.apple.mediaanalysisd", feature: "Media analysis"),
        SimulatorService(id: "nebulad", label: "com.apple.assetsd.nebulad", feature: "Photos asset processing"),

        // Health & fitness
        SimulatorService(id: "healthd", label: "com.apple.healthd", feature: "HealthKit"),
        SimulatorService(id: "fitnesscoachingd", label: "com.apple.fitnesscoachingd", feature: "Fitness coaching"),

        // Home
        SimulatorService(id: "homed", label: "com.apple.homed", feature: "HomeKit"),

        // Messaging
        SimulatorService(id: "identityservicesd", label: "com.apple.identityservicesd", feature: "iMessage & FaceTime"),

        // Widgets
        SimulatorService(id: "chronod", label: "com.apple.chronod", feature: "Widgets"),
        SimulatorService(id: "liveactivitiesd", label: "com.apple.liveactivitiesd", feature: "Live Activities"),

        // Maps & navigation
        SimulatorService(id: "mapssyncd", label: "com.apple.Maps.mapssyncd", feature: "Maps background sync"),
        SimulatorService(id: "navd", label: "com.apple.navd", feature: "Navigation routing"),
        SimulatorService(id: "geod", label: "com.apple.geod", feature: "Geocoding & maps backend"),
        SimulatorService(id: "mapkitsnapshotservice", label: "com.apple.MapKit.SnapshotService", feature: "MapKit snapshot rendering"),

        // Weather, News, Game Center
        SimulatorService(id: "weatherd", label: "com.apple.weatherd", feature: "Weather"),
        SimulatorService(id: "newsd", label: "com.apple.newsd", feature: "News"),
        SimulatorService(id: "gamed", label: "com.apple.gamed", feature: "Game Center"),

        // Find My
        SimulatorService(id: "findmylocated", label: "com.apple.findmy.findmylocated", feature: "Find My"),

        // Screen Time & parental controls
        SimulatorService(id: "screentimeagent", label: "com.apple.ScreenTimeAgent", feature: "Screen Time"),
        SimulatorService(id: "screentimesettingsagent", label: "com.apple.ScreenTimeSettingsAgent", feature: "Screen Time settings"),
        SimulatorService(id: "familycontrolsagent", label: "com.apple.FamilyControlsAgent", feature: "Family controls"),

        // Intelligence & suggestions
        SimulatorService(id: "intelligenceplatformd", label: "com.apple.intelligenceplatformd", feature: "Apple Intelligence platform"),
        SimulatorService(id: "intelligencetasksd", label: "com.apple.intelligencetasksd", feature: "Apple Intelligence tasks"),
        SimulatorService(id: "intelligenceflowd", label: "com.apple.intelligenceflowd", feature: "Apple Intelligence flows"),
        SimulatorService(id: "intelligencecontextd", label: "com.apple.intelligencecontextd", feature: "Apple Intelligence context"),
        SimulatorService(id: "callintelligenced", label: "com.apple.callintelligenced", feature: "Call intelligence"),
        SimulatorService(id: "fitnessintelligenced", label: "com.apple.fitnessintelligenced", feature: "Fitness intelligence"),
        SimulatorService(id: "suggestd", label: "com.apple.suggestd", feature: "Proactive suggestions"),

        // Posters
        SimulatorService(id: "posterboard", label: "com.apple.PosterBoard", feature: "Lock screen & wallpaper posters"),
        SimulatorService(id: "postersyncd", label: "com.apple.contacts.postersyncd", feature: "Contact poster sync"),

        // Generative AI & ML
        SimulatorService(id: "generativeexperiencesd", label: "com.apple.generativeexperiencesd", feature: "Generative AI experiences"),
        SimulatorService(id: "imageplaygroundd", label: "com.apple.imageplaygroundd", feature: "Image Playground generation"),
        SimulatorService(id: "modelcatalogd", label: "com.apple.modelcatalogd", feature: "ML model catalog"),
        SimulatorService(id: "modelmanagerd", label: "com.apple.modelmanagerd", feature: "ML model lifecycle manager"),
        SimulatorService(id: "textunderstandingd", label: "com.apple.textunderstandingd", feature: "Text understanding (Writing Tools)"),
        SimulatorService(id: "hybridsearchd", label: "com.apple.hybridsearchd", feature: "AI-augmented hybrid search"),
        SimulatorService(id: "voicebankingd", label: "com.apple.voicebankingd", feature: "Personal Voice banking"),
        SimulatorService(id: "translationd", label: "com.apple.translationd", feature: "Translation"),
        SimulatorService(id: "mlhostd", label: "com.apple.mlhostd", feature: "ML model host"),
        SimulatorService(id: "mlruntimed", label: "com.apple.mlruntimed", feature: "ML runtime"),
        SimulatorService(id: "knowledgeconstructiond", label: "com.apple.knowledgeconstructiond", feature: "Knowledge graph construction"),
        SimulatorService(id: "agentstored", label: "com.apple.GenerativeFunctions.agentstored", feature: "Generative AI agent store"),
        SimulatorService(id: "contentlinkingd", label: "com.apple.synapse.contentlinkingd", feature: "Synapse content linking"),
        SimulatorService(id: "naturallanguaged", label: "com.apple.naturallanguaged", feature: "Natural language processing"),

        // Apple Watch companion.
        //
        // Every daemon in `/System/Library/NanoLaunchDaemons` ships with `Disabled => true`,
        // so they are off by default and only run because `nanoregistrylaunchd` scans that
        // directory and enables the whole thing (`launch_enable_directory`). It is on-demand
        // (`RunAtLoad => false`), so it fires whenever its client first pokes it — well after
        // a readiness wait returns — and its `enable` beats any `disable` written earlier.
        //
        // Disabling the enabler is therefore the only thing that sticks, and it stops the
        // others without naming them. The individual labels below are kept so existing
        // configurations keep resolving, but on their own they lose the race.
        SimulatorService(id: "nanoregistrylaunchd", label: "com.apple.nanoregistrylaunchd", feature: "Watch registry launcher (gates every Watch companion daemon)"),
        SimulatorService(id: "nanomapscd", label: "com.apple.nanomapscd", feature: "Watch Maps companion"),
        SimulatorService(id: "nanosystemsettingsd", label: "com.apple.nanosystemsettingsd", feature: "Watch system settings"),
        SimulatorService(id: "npkcompanionagent", label: "com.apple.NPKCompanionAgent", feature: "Watch companion agent"),
        SimulatorService(id: "companionappd", label: "com.apple.companionappd", feature: "Watch companion app"),
        SimulatorService(id: "brookcompaniond", label: "com.apple.brook.brookcompaniond", feature: "Brook companion (Watch)"),
        SimulatorService(id: "appconduitd", label: "com.apple.appconduitd", feature: "App conduit (Watch)"),
        SimulatorService(id: "nanoappregistryd", label: "com.apple.nanoappregistryd", feature: "Watch app registration"),
        SimulatorService(id: "nanonewscd", label: "com.apple.nanonewscd", feature: "Watch News companion"),
        SimulatorService(id: "pairedsyncd", label: "com.apple.pairedsyncd", feature: "Paired device sync"),
        SimulatorService(id: "pairedunlockd", label: "com.apple.pairedunlockd", feature: "Paired unlock"),
        SimulatorService(id: "companiond", label: "com.apple.companiond", feature: "Companion device daemon"),
        SimulatorService(id: "companionmessagesd", label: "com.apple.companionmessagesd", feature: "Watch companion messages"),
        SimulatorService(id: "companionfindlocallyd", label: "com.apple.companionfindlocallyd", feature: "Companion find locally"),

        // Ads & promoted content
        SimulatorService(id: "promotedcontentd", label: "com.apple.ap.promotedcontentd", feature: "Promoted content & ads"),
        SimulatorService(id: "adprivacyd", label: "com.apple.ap.adprivacyd", feature: "Ad privacy"),

        // MDM & device management
        SimulatorService(id: "remotemanagementd", label: "com.apple.remotemanagementd", feature: "Remote management (MDM)"),

        // Safari
        SimulatorService(id: "safaribookmarkssyncagent", label: "com.apple.SafariBookmarksSyncAgent", feature: "Safari bookmark sync"),

        // System background
        SimulatorService(id: "mobileassetd", label: "com.apple.mobileassetd", feature: "OTA asset delivery")
    ]

    static let groups: [SimulatorServiceGroup] = [
        SimulatorServiceGroup(id: "payments", feature: "StoreKit / in-app purchase", serviceIDs: [
            "storekitd", "itunesstored", "amsaccountsd", "amsengagementd", "amsondevicestoraged", "passd", "financed", "merchantd"
        ]),
        SimulatorServiceGroup(id: "app-store", feature: "App Store", serviceIDs: ["appstored", "itunesstored"]),
        SimulatorServiceGroup(id: "spotlight", feature: "Spotlight & search", serviceIDs: [
            "searchd", "searchtoold", "spotlightknowledgedupdater", "parsecd"
        ]),
        SimulatorServiceGroup(id: "siri", feature: "Siri & speech", serviceIDs: [
            "assistantd", "corespeechd", "siriinferenced", "siriknowledged", "siriactionsd", "sirittsd", "siricontextd", "siriacousticsignatured"
        ]),
        SimulatorServiceGroup(id: "photos", feature: "Photos library & analysis", serviceIDs: [
            "assetsd", "photoanalysisd", "mediaanalysisd", "nebulad"
        ]),
        SimulatorServiceGroup(id: "health", feature: "HealthKit & fitness", serviceIDs: [
            "healthd", "fitnesscoachingd"
        ]),
        SimulatorServiceGroup(id: "maps", feature: "Maps & navigation", serviceIDs: [
            "mapssyncd", "navd", "geod", "mapkitsnapshotservice"
        ]),
        SimulatorServiceGroup(id: "widgets", feature: "Widgets & Live Activities", serviceIDs: ["chronod", "liveactivitiesd"]),
        SimulatorServiceGroup(id: "intelligence", feature: "Apple Intelligence", serviceIDs: [
            "intelligenceplatformd", "intelligencetasksd", "intelligenceflowd", "intelligencecontextd",
            "callintelligenced", "fitnessintelligenced", "suggestd"
        ]),
        SimulatorServiceGroup(id: "posters", feature: "Lock screen & wallpaper posters", serviceIDs: ["posterboard", "postersyncd"]),
        SimulatorServiceGroup(id: "generative", feature: "Generative AI & ML models", serviceIDs: [
            "generativeexperiencesd", "imageplaygroundd", "modelcatalogd", "modelmanagerd", "textunderstandingd",
            "hybridsearchd", "voicebankingd", "translationd", "mlhostd", "mlruntimed",
            "knowledgeconstructiond", "agentstored", "contentlinkingd", "naturallanguaged"
        ]),
        SimulatorServiceGroup(id: "ads", feature: "Ads & promoted content", serviceIDs: [
            "promotedcontentd", "adprivacyd"
        ]),
        // `nanoregistrylaunchd` first: it is the one that actually keeps the rest down.
        SimulatorServiceGroup(id: "watch", feature: "Apple Watch companion services", serviceIDs: [
            "nanoregistrylaunchd",
            "nanomapscd", "nanosystemsettingsd", "npkcompanionagent", "companionappd", "brookcompaniond",
            "appconduitd", "nanoappregistryd", "nanonewscd", "pairedsyncd", "pairedunlockd",
            "companiond", "companionmessagesd", "companionfindlocallyd"
        ])
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

    /// The transitions needed to move a simulator from its currently disabled set to
    /// the desired one.
    struct Delta: Equatable {
        let toDisable: [String]
        let toEnable: [String]

        var isEmpty: Bool {
            toDisable.isEmpty && toEnable.isEmpty
        }
    }

    /// Computes the delta between the observed disabled set and the desired one, scoped
    /// to the managed allowlist in both directions: a desired label outside the
    /// allowlist is never disabled, and an unmanaged label that is already disabled is
    /// left alone.
    ///
    /// - Parameters:
    ///   - current: labels currently disabled on the device (as read from launchd).
    ///   - desired: labels that should end up disabled.
    /// - Returns: labels to disable (want off, is on) and to enable (is off, want on),
    ///   sorted for determinism.
    static func delta(current: Set<String>, desired: Set<String>) -> Delta {
        Delta(toDisable: desired.intersection(managed).subtracting(current).sorted(),
              toEnable: current.intersection(managed).subtracting(desired).sorted())
    }
}
