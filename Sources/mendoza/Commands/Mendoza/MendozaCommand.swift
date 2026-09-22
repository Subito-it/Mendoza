//
//  MendozaCommand.swift
//  Mendoza
//
//  Created by Tomas Camin on 20/09/2019.
//

import AppKit
import Bariloche
import CachiKit
import CoreGraphics
import Foundation

class MendozaCommand: Command {
    let name: String? = "mendoza"
    let usage: String? = "Mendoza internally used commands"
    let help: String? = "Internal"

    let commandName = Argument<String>(name: "command_name", kind: .positional, optional: false)
    let parameters = Argument<[String]>(name: "parameters", kind: .variadic, optional: true)

    func run() -> Bool {
        switch commandName.value {
        case "run_test_batch":
            guard let paths = parameters.value?.filter({ !$0.isEmpty }), paths.count == 1 else { return false }
            do {
                try BatchWorker.run(requestPath: paths[0])
                return true
            } catch {
                print("Batch worker failed: \(error)")
                return false
            }
        case "screen_point_size":
            let mainID = CGMainDisplayID()
            let maxDisplays: UInt32 = 16
            var displays: [CGDirectDisplayID] = [mainID]
            var displayCount: UInt32 = 0

            guard CGGetOnlineDisplayList(maxDisplays, &displays, &displayCount) == .success else {
                return false
            }

            for currentDisplay in displays {
                let height = CGDisplayPixelsHigh(currentDisplay)
                let width = CGDisplayPixelsWide(currentDisplay)

                print(#"{ "width": \#(width), "height": \#(height) }"#)

                return true
            }

            return false
        case "simulator_locations":
            let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, CGWindowListOption.optionOnScreenOnly)

            guard let info = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
                return false
            }

            var result = [[String: Int]]()

            // On Catalina, unless you enable screen recording permissions,
            // you no longer get kCGWindowName access for security reasons
            //
            // Matches Simulator.app only: on Xcode 27 DeviceHub never shows simulators booted via
            // simctl, so its only window is the management window, which is not a simulator
            for dict in info where dict["kCGWindowOwnerName"] as? String == "Simulator" {
                guard let windowBoundsInfo = dict["kCGWindowBounds"] as? [String: Int] else {
                    return false
                }

                result.append(windowBoundsInfo)
            }

            guard let data = try? JSONEncoder().encode(result) else { return false }
            print(String(decoding: data, as: UTF8.self))

            return true
        case "close_simulator_app":
            // com.apple.dt.Devices is DeviceHub, which replaced Simulator.app in Xcode 27
            let runningApps = ["com.apple.iphonesimulator", "com.apple.dt.Devices"]
                .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }

            for runningApp in runningApps {
                runningApp.terminate()
            }

            return true
        case "coresimulator":
            // Usage: coresimulator <device_udid> <developer_dir> <key=value> [<key=value> ...]
            //
            // Applies settings through CoreSimulator.framework, which must run on the node owning
            // the simulator. Unavailable selectors are reported but do not fail the command, so a
            // future Xcode dropping one degrades rather than breaking the run.
            guard let parameters = parameters.value?.filter({ !$0.isEmpty }), parameters.count >= 3 else {
                print("Expecting <device_udid> <developer_dir> <key=value> [<key=value> ...]")
                return false
            }

            let deviceIdentifier = parameters[0]
            let developerDir = parameters[1]
            var succeeded = true

            for rawSetting in parameters.dropFirst(2) {
                guard let setting = CoreSimulatorProxy.Setting(rawValue: rawSetting) else {
                    print("Unsupported setting '\(rawSetting)'")
                    succeeded = false
                    continue
                }

                switch CoreSimulatorProxy.apply(setting, deviceIdentifier: deviceIdentifier, developerDir: developerDir) {
                case .success:
                    print("\(setting.name): ok")
                case .unavailable:
                    print("\(setting.name): unavailable in this Xcode version")
                case let .failure(message):
                    print("\(setting.name): failed (\(message))")
                    succeeded = false
                }
            }

            return succeeded
        case "cleaunp_xcresult":
            guard let parameters = parameters.value?.filter({ !$0.isEmpty }), parameters.count == 2 else {
                return false
            }

            let xcresultPath = parameters[0]
            guard FileManager.default.fileExists(atPath: xcresultPath) else {
                print("\(xcresultPath) does not exist")
                return false
            }
            guard let sizeKb = Int(parameters[1]), sizeKb > 1 else {
                print("Invalid size parameter")
                return false
            }

            /// Cleanup can remove all files except the attachment to the test actions
            /// which are used to present testing steps
            ///
            /// Below we extract the ids of those attachments out of the xcresult
            /// and rewrite all files exceeding the threshold size with an marker string

            let cleaner = XcResultCleaner(path: xcresultPath)

            do {
                try cleaner.clean(minimumSizeKB: sizeKb)
            } catch {
                print("xcresult cleanup failed: \(error)")
                return false
            }

            print("MENDOZA_XCRESULT_CLEANED")
            return true
        case "extract_files_coverage":
            guard let parameters = parameters.value?.filter({ !$0.isEmpty }), parameters.count == 2 else {
                return false
            }

            do {
                let sourcePath = parameters[0]
                let destinationPath = parameters[1]

                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: sourcePath))) as? [String: Any]
                let data = json?["data"] as? [[String: Any]]
                let firstData = data?.first
                let files = firstData?["files"] as? [[String: Any]]

                guard let files else { return false }

                var coveredFiles = [[String: Double]]()
                for file in files {
                    let filename = file["filename"] as? String
                    let summary = file["summary"] as? [String: Any]
                    let lines = summary?["lines"] as? [String: Any]
                    let coveredLines = lines?["covered"] as? Int
                    let percent = lines?["percent"] as? Double

                    guard let filename, let coveredLines, let percent else { continue }

                    if coveredLines > 0 {
                        coveredFiles.append([filename: percent])
                    }
                }

                let destinationData = try JSONEncoder().encode(coveredFiles)
                try destinationData.write(to: URL(filePath: destinationPath))

                return true
            } catch {
                return false
            }
        default:
            return false
        }
    }
}

class XcResultCleaner {
    let url: URL
    private let readInvocationRecord: () throws -> ActionsInvocationRecord
    private let readPlanSummaries: (String) throws -> ActionTestPlanRunSummaries
    private let readTestSummary: (String) throws -> ActionTestSummary

    init(path: String) {
        url = URL(fileURLWithPath: path)
        let reader = CachiKit(url: url)
        readInvocationRecord = reader.actionsInvocationRecord
        readPlanSummaries = reader.actionTestPlanRunSummaries
        readTestSummary = reader.actionTestSummary
    }

    init(path: String, readObject: @escaping (String?) throws -> Data) {
        url = URL(fileURLWithPath: path)
        func decode<T: Decodable>(_ type: T.Type, identifier: String?) throws -> T {
            try JSONDecoder().decode(type, from: readObject(identifier))
        }
        readInvocationRecord = { try decode(ActionsInvocationRecord.self, identifier: nil) }
        readPlanSummaries = { try decode(ActionTestPlanRunSummaries.self, identifier: $0) }
        readTestSummary = { try decode(ActionTestSummary.self, identifier: $0) }
    }

    func clean(minimumSizeKB: Int) throws {
        guard minimumSizeKB > 1, minimumSizeKB <= Int.max / 1024 else { throw "Invalid xcresult cleanup threshold" }
        let invocationRecord = try readInvocationRecord()

        var attachmentIdentifiers = [String]()

        for action in invocationRecord.actions {
            guard let testRef = action.actionResult.testsRef else { continue }
            attachmentIdentifiers += try protectedTestIdentifiers(for: testRef.id)
        }
        guard !attachmentIdentifiers.isEmpty else { throw "No test summaries; preserving all blobs" }

        var urls = extractFiles(at: url.appendingPathComponent("Data"), recursively: true)

        // Filter out files that are used in action attachments
        urls = urls.filter { url in !attachmentIdentifiers.contains(where: { identifier in url.lastPathComponent.contains(identifier) }) }

        for url in urls {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }

            if size > minimumSizeKB * 1024 {
                try Data("content replaced by mendoza because original file was larger than \(minimumSizeKB)KB".utf8).write(to: url, options: .atomic)
            }
        }
    }

    /// Resolve every summary before modifying any blob, so a decoding failure cannot cause partial cleanup.
    func protectedTestIdentifiers(for testRef: String) throws -> [String] {
        let plans = try readPlanSummaries(testRef)
        let identifiers = plans.summaries.flatMap { plan in
            plan.testableSummaries.flatMap { extractTestSummaryIdentifiers(actionTestSummariesGroup: $0.tests) }
        }
        guard !identifiers.isEmpty else { throw "Failed extracting test summaries; preserving all blobs" }
        var protected = [testRef] + identifiers
        for identifier in Set(identifiers) {
            let summary = try readTestSummary(identifier)
            protected += extractActivitiesAttachmentIdentifiers(summary.activitySummaries)
            for failure in summary.failureSummaries {
                protected += extractAttachmentIdentifiers(failure.attachments)
            }
        }
        return protected
    }

    func extractFiles(at url: URL, recursively: Bool) -> [URL] {
        var result = [URL]()

        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])

            if recursively {
                let subdirectories = try contents.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
                result += subdirectories.map { extractFiles(at: $0, recursively: recursively) }.flatMap { $0 }
            }

            result += try contents.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == false }
        } catch {
            print("Error reading folder contents: \(error)")
        }

        return result
    }

    private func extractTestSummaryIdentifiers(actionTestSummariesGroup: [ActionTestSummaryGroup]) -> [String] {
        var result = [String]()

        for group in actionTestSummariesGroup {
            for child in group.subtests {
                if let test = child as? ActionTestMetadata, let identifier = test.summaryRef?.id {
                    result.append(identifier)
                } else if let group = child as? ActionTestSummaryGroup {
                    result += extractTestSummaryIdentifiers(actionTestSummariesGroup: [group])
                }
            }
        }

        return result
    }

    private func extractActivitiesAttachmentIdentifiers(_ activities: [ActionTestActivitySummary]) -> [String] {
        var result = [String]()

        for activity in activities {
            result += extractAttachmentIdentifiers(activity.attachments)
            result += extractActivitiesAttachmentIdentifiers(activity.subactivities)
        }

        return result
    }

    private func extractAttachmentIdentifiers(_ attachments: [ActionTestAttachment]) -> [String] {
        attachments.compactMap { $0.payloadRef?.id }
    }
}

extension String: Swift.Error {}
