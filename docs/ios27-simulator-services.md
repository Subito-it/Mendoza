# iOS 27 Simulator Services — Memory Usage Audit

Device: iPhone (UUID `EE2BCB7C-18A6-468C-9A56-CF4054E9A34A`), iOS 27, idle state.
Date: 2026-08-25

Memory is RSS (Resident Set Size) in MB, measured via `ps -o rss` on the host after the simulator had been idle.

## Running Services (sorted by memory, descending)

| RSS (MB) | Label | Feature | In Catalog |
|----------|-------|---------|:----------:|
| 444.0 | com.apple.SpringBoard | Home screen / UI host | — |
| 232.6 | com.apple.PosterBoard | Lock screen & wallpaper posters | ✓ |
| 218.9 | com.apple.email.maild | Mail | ✓ |
| 218.3 | com.apple.assistantd | Siri | ✓ |
| 211.0 | com.apple.siriactionsd | Siri actions | ✓ |
| 206.4 | com.apple.intelligenceflowd | Apple Intelligence flows | ✓ |
| 185.6 | com.apple.sharingd | AirDrop & proximity sharing | — |
| 181.7 | com.apple.chronod | Widgets | ✓ |
| 179.7 | com.apple.MapKit.SnapshotService | MapKit snapshot rendering | ✓ |
| 178.4 | com.apple.calaccessd | Calendar | ✓ |
| 173.5 | com.apple.icloudmailagent | iCloud Mail sync | ✓ |
| 170.4 | com.apple.siriinferenced | Siri inference | ✓ |
| 169.8 | com.apple.remindd | Reminders | ✓ |
| 168.8 | com.apple.homed | HomeKit | ✓ |
| 155.1 | com.apple.routined | Location routine learning | — |
| 152.5 | com.apple.ScreenTimeAgent | Screen Time | ✓ |
| 151.1 | com.apple.nanomapscd | Watch Maps companion | ✓ |
| 149.5 | com.apple.passd | Wallet & passes | ✓ |
| 147.8 | com.apple.nanosystemsettingsd | Watch system settings | ✓ |
| 142.9 | com.apple.InputUI | Keyboard / input UI | — |
| 142.4 | com.apple.healthd | HealthKit | ✓ |
| 140.8 | com.apple.searchd | Spotlight search | ✓ |
| 139.7 | com.apple.intelligencecontextd | Apple Intelligence context | ✓ |
| 139.5 | com.apple.telephonyutilities.callservicesd | Phone call services | — |
| 138.3 | com.apple.suggestd | Proactive suggestions | ✓ |
| 136.3 | com.apple.donotdisturbd | Focus / Do Not Disturb | — |
| 135.9 | com.apple.amsengagementd | Apple Media Services engagement | ✓ |
| 128.8 | com.apple.imageplaygroundd | Image Playground generation | ✓ |
| 118.5 | com.apple.generativeexperiencesd | Generative AI experiences | ✓ |
| 116.8 | com.apple.NPKCompanionAgent | Watch companion agent | ✓ |
| 116.5 | com.apple.AuthenticationServicesCore.AuthenticationServicesAgent | Passkeys / auth UI | — |
| 115.4 | com.apple.intelligenceplatformd | Apple Intelligence platform | ✓ |
| 114.0 | com.apple.newsd | News | ✓ |
| 113.9 | com.apple.biomed | Biometric & health data | — |
| 112.6 | com.apple.storekitd | StoreKit | ✓ |
| 110.7 | com.apple.locationd | Location services | — |
| 110.4 | com.apple.dataaccess.dataaccessd | Exchange & data access | ✓ |
| 110.1 | com.apple.merchantd | Apple Pay merchant | ✓ |
| 108.5 | com.apple.liveactivitiesd | Live Activities | ✓ |
| 107.9 | com.apple.AccessibilityUIServer | Accessibility UI | — |
| 107.7 | com.apple.financed | Finance datastore | ✓ |
| 105.7 | com.apple.navd | Navigation routing | ✓ |
| 104.9 | com.apple.gamed | Game Center | ✓ |
| 104.1 | com.apple.linkd | Universal links | — |
| 103.1 | com.apple.usernotificationsd | User notifications | — |
| 102.9 | com.apple.iconservices.iconservicesagent | Icon cache | — |
| 98.8 | com.apple.weatherd | Weather | ✓ |
| 98.3 | com.apple.ScreenTimeSettingsAgent | Screen Time settings | ✓ |
| 97.8 | com.apple.mobileassetd | OTA asset delivery | ✓ |
| 97.5 | com.apple.managedconfiguration.profiled | MDM profiles | — |
| 97.4 | com.apple.spotlightknowledged.updater | Spotlight knowledge updater | ✓ |
| 96.7 | com.apple.accessibility.axassetsd | Accessibility assets | — |
| 96.3 | com.apple.amsaccountsd | Apple Media Services accounts | ✓ |
| 96.3 | com.apple.bulletindistributord | Notification routing | — |
| 96.0 | com.apple.nanotimekitcompaniond | Watch clock companion | — |
| 95.6 | com.apple.FamilyControlsAgent | Family controls | ✓ |
| 95.3 | com.apple.peopled | People suggestions | ✓ |
| 94.5 | com.apple.corespeechd | Speech recognition | ✓ |
| 93.2 | com.apple.backboardd | HID / display compositor | — |
| 91.5 | com.apple.appstored | App Store | ✓ |
| 90.8 | com.apple.fitnesscoachingd | Fitness coaching | ✓ |
| 89.6 | com.apple.sirittsd | Siri text-to-speech | ✓ |
| 87.6 | com.apple.siriknowledged | Siri knowledge | ✓ |
| 87.3 | com.apple.addressbooksyncd | Address book sync | ✓ |
| 86.6 | com.apple.companionappd | Watch companion app | ✓ |
| 86.5 | com.apple.mediaremoted | Media remote control | — |
| 86.5 | com.apple.translationd | Translation | ✓ |
| 86.3 | com.apple.cloudd | iCloud sync | ✓ |
| 85.6 | com.apple.assetsd.nebulad | Photos asset processing | ✓ |
| 83.7 | com.apple.itunescloudd | iTunes Cloud sync | ✓ |
| 83.6 | com.apple.ap.promotedcontentd | Promoted content & ads | ✓ |
| 82.9 | com.apple.modelcatalogd | ML model catalog | ✓ |
| 81.8 | com.apple.parsecd | Parsec search ranking | ✓ |
| 81.7 | com.apple.coreidvd | Core identity verification | — |
| 81.2 | com.apple.itunesstored | iTunes Store backend | ✓ |
| 80.2 | com.apple.fitnessintelligenced | Fitness intelligence | ✓ |
| 80.1 | com.apple.mobiletimerd | Timer / alarms | — |
| 78.0 | com.apple.appleaccountd | Apple Account daemon | — |
| 74.8 | com.apple.identityservicesd | iMessage & FaceTime | ✓ |
| 74.8 | com.apple.FileProvider | File provider coordination | — |
| 74.3 | com.apple.assetsd | Photos library | ✓ |
| 72.4 | com.apple.mediaanalysisd | Media analysis | ✓ |
| 72.4 | com.apple.dasd | Duet Activity Scheduler | — |
| 70.6 | com.apple.geod | Geocoding & maps backend | ✓ |
| 70.2 | com.apple.sociallayerd | Social layer / contact sharing | — |
| 69.6 | com.apple.voicebankingd | Personal Voice banking | ✓ |
| 67.7 | com.apple.SafariBookmarksSyncAgent | Safari bookmark sync | ✓ |
| 67.0 | com.apple.rapportd | Device proximity / Handoff | — |
| 66.9 | com.apple.diagnosticextensionsd | Diagnostic extensions | — |
| 65.3 | com.apple.contactsd | Contacts | ✓ |
| 65.0 | com.apple.textunderstandingd | Text understanding (Writing Tools) | ✓ |
| 64.8 | com.apple.modelmanagerd | ML model lifecycle manager | ✓ |
| 64.6 | com.apple.fileindexerd | File indexing | — |
| 64.5 | com.apple.WebBookmarks.webbookmarksd | Web bookmarks | — |
| 64.4 | com.apple.syncdefaultsd | Defaults sync | — |
| 63.7 | com.apple.findmy.findmylocated | Find My | ✓ |
| 63.3 | com.apple.remotemanagementd | Remote management (MDM) | ✓ |
| 63.1 | com.apple.hybridsearchd | AI-augmented hybrid search | ✓ |
| 62.9 | com.apple.ap.adprivacyd | Ad privacy | ✓ |
| 62.6 | com.apple.homeeventsd | Home automation events | — |
| 62.5 | com.apple.Safari.passwordbreachd | Safari password breach check | — |
| 61.5 | com.apple.jetpackassetd | Jetpack asset daemon | — |
| 61.3 | com.apple.protectedcloudstorage.protectedcloudkeysyncing | Protected cloud key sync | — |
| 60.5 | com.apple.brook.brookcompaniond | Brook companion | ✓ |
| 57.5 | com.apple.medialibraryd | Media library | — |
| 56.5 | com.apple.deviceaccessd | Device access daemon | — |
| 55.9 | com.apple.finhealthd | Financial health | — |
| 55.7 | com.apple.managedassetsd | Managed assets (MDM) | — |
| 55.6 | com.apple.sleepd | Sleep tracking | — |
| 55.3 | com.apple.photoanalysisd | Photos analysis | ✓ |
| 55.1 | com.apple.ManagedSettingsAgent | Managed settings (MDM) | — |
| 54.6 | com.apple.wcd | Web credentials | — |
| 53.6 | com.apple.geoanalyticsd | Geo analytics | — |
| 53.5 | com.apple.avatarsd | Memoji / avatars | — |
| 53.4 | com.apple.Safari.SafeBrowsing.Service | Safari Safe Browsing | — |
| 52.9 | com.apple.familycircled | Family Circle | — |
| 52.4 | com.apple.runningboardd | Process lifecycle (runningboard) | — |
| 52.0 | com.apple.AppSSODaemon | App single sign-on | — |
| 51.8 | com.apple.spotlightknowledged | Spotlight knowledge | — |
| 51.5 | com.apple.DeviceConfigurationAgent | Device configuration | — |
| 50.7 | com.apple.securityd | Security daemon | — |
| 50.4 | com.apple.biomesyncd | Biome sync | — |
| 49.4 | com.apple.TextInput.kbd | Keyboard daemon | — |
| 49.1 | com.apple.eligibilityd | Feature eligibility | — |
| 48.8 | com.apple.communicationtrustd | Communication safety | — |
| 46.8 | com.apple.lsd | Launch Services | — |
| 46.7 | com.apple.ctkd | CryptoTokenKit | — |
| 46.3 | com.apple.eventkitsyncd | Calendar sync | — |
| 45.9 | com.apple.triald | Feature trials / experiments | — |
| 44.9 | com.apple.dmd | Device management | — |
| 44.0 | com.apple.nsurlsessiond | Background URL sessions | — |
| 43.3 | com.apple.pasteboard.pasted | Pasteboard daemon | — |
| 42.9 | com.apple.coredevice.dtdeviceinfod | CoreDevice info | — |
| 42.4 | com.apple.CoreSimulator.bridge | Simulator bridge | — |
| 42.3 | com.apple.appprotectiond | App protection | — |
| 42.3 | com.apple.bird | CloudKit assets | — |
| 40.3 | com.apple.GameController.gamecontrollerd | Game controller daemon | — |
| 40.1 | com.apple.siri.context.service | Siri context | ✓ |
| 39.9 | com.apple.apsd | Push notifications | ✓ |
| 39.1 | com.apple.localizationswitcherd | Localization switcher | — |
| 38.8 | com.apple.akd | iCloud Keychain / Apple account auth | ✓ |
| 37.6 | com.apple.featureaccessd | Feature access control | — |
| 37.5 | com.apple.ClipServices.clipserviced | App Clips | — |
| 36.7 | com.apple.UsageTrackingAgent | Usage tracking | — |
| 36.5 | com.apple.nanoregistryd | Watch registration | — |
| 36.2 | com.apple.ind | Input daemon | — |
| 35.9 | com.apple.cdpd | Continuity / cloud device pairing | — |
| 34.7 | com.apple.tccd | Privacy (TCC) daemon | — |
| 34.4 | com.apple.nanoprefsyncd.2 | Watch preferences sync | — |
| 34.3 | com.apple.pluginkit.pkd | PluginKit daemon | — |
| 33.9 | com.apple.assistant_cdmd | Assistant command daemon | — |
| 33.0 | com.apple.assetsubscriptiond | Asset subscription | — |
| 30.8 | com.apple.swcd | Universal links / associated domains | ✓ |
| 30.6 | com.apple.UserEventAgent-System | System event agent | — |
| 29.5 | com.apple.installcoordinationd | Install coordination | — |
| 29.4 | com.apple.appconduitd | App conduit (Watch) | ✓ |
| 29.2 | com.apple.FileCoordination | File coordination | — |
| 25.7 | com.apple.systemstatusd | System status | — |
| 25.0 | com.apple.accountsd | Accounts daemon | — |
| 24.6 | com.apple.replicatord | Replicator | — |
| 24.0 | com.apple.devicecheckd | DeviceCheck | — |
| 23.0 | com.apple.trustd | Certificate trust | — |
| 18.0 | com.apple.revisiond | Vision framework daemon | — |
| 17.5 | com.apple.containermanagerd | Container manager | — |
| 16.7 | com.apple.countryd | Country detection | — |
| 13.7 | com.apple.fontservicesd | Font services | — |
| 13.7 | com.apple.GSSCred | GSS credentials | — |
| 13.2 | com.apple.webprivacyd | Web privacy | — |
| 13.0 | com.apple.followupd | Follow-up actions | — |
| 12.8 | com.apple.accessibility.mediaaccessibilityd | Media accessibility | — |
| 12.8 | com.apple.purplebuddy.budd | Setup assistant | — |
| 11.2 | com.apple.nanoregistrylaunchd | Watch registry launcher | ✓ |
| 11.0 | com.apple.ids_simd | IDS sim bridge | — |
| 10.5 | com.apple.mobile.installd | App installer | — |
| 10.0 | com.apple.cfprefsd.xpc.daemon | Preferences daemon | — |
| 9.0 | com.apple.configd_sim | Network config (sim) | — |
| 6.2 | com.apple.MobileInstallationHelperService | Installation helper | — |
| 5.1 | com.apple.distnoted.xpc.daemon | Distributed notifications | — |
| 3.4 | com.apple.aslmanager | ASL log manager | — |
| 1.2 | com.apple.syslogd | Syslog daemon | — |

## Registered But Not Running (on-demand)

These services are registered in launchd but not currently running. They launch on demand and would consume memory only when triggered.

| Label | Feature |
|-------|---------|
| com.apple.amsondevicestoraged | Apple Media Services on-device storage |
| com.apple.callintelligenced | Call intelligence |
| com.apple.contacts.postersyncd | Contact poster sync |
| com.apple.GenerativeFunctions.agentstored | Generative AI agent store |
| com.apple.intelligencetasksd | Apple Intelligence tasks |
| com.apple.knowledgeconstructiond | Knowledge graph construction |
| com.apple.Maps.mapssyncd | Maps background sync |
| com.apple.mlhostd | ML model host |
| com.apple.mlruntimed | ML runtime |
| com.apple.musicd | Music daemon |
| com.apple.naturallanguaged | Natural language processing |
| com.apple.searchtoold | Settings search |
| com.apple.shazamd | Shazam music recognition |
| com.apple.shazameventsd | Shazam events |
| com.apple.siri.acousticsignature | Siri acoustic signature |
| com.apple.synapse.contentlinkingd | Synapse content linking |
| com.apple.testmanagerd | XCTest host (testing infra) |
| com.apple.tipsd | Tips |
| com.apple.translationd | Translation (on-demand) |
| com.apple.tvremoted | Apple TV remote |
| com.apple.cloudphotod | iCloud Photo Library sync |
| com.apple.mediaanalysisd.service | Media analysis service |

## The Watch companion family is gated by a single daemon

Every daemon in `/System/Library/NanoLaunchDaemons` ships with `Disabled => true` in its own
plist. They run only because `com.apple.nanoregistrylaunchd` scans that directory and enables
the lot. Because it is on-demand (`RunAtLoad => false`) it fires well after a boot-readiness
wait returns, so its `enable` overwrites any `disable` written earlier — which is why the
individual Watch labels could not be kept disabled on their own.

Disabling the enabler keeps all of them down, survives reboots, and needs no per-boot
follow-up. Measured on iOS 26.2: ~432 MB RSS per simulator. The effect also reaches on-demand
clients that are not in that directory — notably `nanotimekitcompaniond` (96 MB here, 132 MB
on the 26.2 probe), which is otherwise excluded from the catalog because disabling it directly
wedges the simulator.

Note that `launchctl print-disabled` reports only *overrides*, never the plist-level
`Disabled` default, so it cannot be used to tell whether a service will actually run. Use
`plutil -extract Disabled raw` on the job's plist for that.

## Notes

- RSS is not additive across processes due to shared memory pages, but gives a useful relative ranking.
- On-demand services (not running) would add further memory pressure when triggered.
- The catalog now covers 95 services across 13 groups. Of the 192 running services observed, 79 are in the catalog (total RSS ~8.9 GB), leaving 113 uncatalogued (total RSS ~6.3 GB). Uncatalogued services above 60 MB that were deliberately excluded: `locationd` (breaks CLLocationManager mocking), `AccessibilityUIServer` (XCUITest depends on it), `backboardd` (display compositor — simulator won't function), `usernotificationsd` (needed for notification-delivery assertions), `dasd` (system-critical task scheduler), `routined`/`biomed`/`nanotimekitcompaniond`/`managedconfiguration.profiled` (wedge the simulator when disabled), `sharingd` (removed from the catalog — `UIActivityViewController` queries it synchronously to populate its share sheet; disabling it leaves the sheet empty, breaking the system Copy action and any other activity, in any app that presents a share sheet).
- The `generative` group (14 services) totals ~690 MB of the running subset when all are resident.
- The `watch` group (13 services) totals ~660 MB of the running subset.
- The `maps` group (4 services: mapssyncd, navd, geod, mapkitsnapshotservice) totals ~356 MB when all are resident.
- The `health` group (2 services: healthd, fitnesscoachingd) totals ~233 MB.
- The `intelligence` group (7 services, including suggestd) totals ~1.0 GB.
