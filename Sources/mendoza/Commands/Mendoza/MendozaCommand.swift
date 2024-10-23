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
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator")

            for runningApp in runningApps {
                runningApp.terminate()
            }

            return true
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
                return false
            }

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

                var coveredFiles = [String]()
                for file in files {
                    let filename = file["filename"] as? String
                    let summary = file["summary"] as? [String: Any]
                    let lines = summary?["lines"] as? [String: Any]
                    let coveredLines = lines?["covered"] as? Int

                    guard let filename, let coveredLines else { continue }

                    if coveredLines > 0 {
                        coveredFiles.append(filename)
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

    init(path: String) {
        url = URL(fileURLWithPath: path)
    }

    func clean(minimumSizeKB: Int) throws {
        let cachi = CachiKit(url: url)

        let invocationRecord = try cachi.actionsInvocationRecord()

        var attachmentIdentifiers = [String]()

        for action in invocationRecord.actions {
            guard let testRef = action.actionResult.testsRef else { continue }

            guard let testPlanSummaries = (try? cachi.actionTestPlanRunSummaries(identifier: testRef.id))?.summaries,
                  let testPlanSummary = testPlanSummaries.first,
                  testPlanSummaries.count == 1,
                  let testableSummary = testPlanSummary.testableSummaries.first,
                  testPlanSummary.testableSummaries.count == 1
            else {
                throw "Failed extracting test testPlanSummary"
            }

            let testSummaryIdentifiers = extractTestSummaryIdentifiers(actionTestSummariesGroup: testableSummary.tests)
            guard testSummaryIdentifiers.count == 1,
                  let testSummaryIdentifier = testSummaryIdentifiers.first,
                  let testSummary = try? cachi.actionTestSummary(identifier: testSummaryIdentifier)
            else {
                throw "Failed extracting test testSummary"
            }

            attachmentIdentifiers += extractActivitiesAttachmentIdentifiers(testSummary.activitySummaries)
            for failureSummary in testSummary.failureSummaries {
                attachmentIdentifiers += extractAttachmentIdentifiers(failureSummary.attachments)
            }
        }

        var urls = extractFiles(at: url.appendingPathComponent("Data"), recursively: true)

        // Filter out files that are used in action attachments
        urls = urls.filter { url in !attachmentIdentifiers.contains(where: { identifier in url.lastPathComponent.contains(identifier) }) }

        for url in urls {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }

            if size > minimumSizeKB * 1024 {
                try? Data("content replaced by mendoza because original file was larger than \(minimumSizeKB)KB".utf8).write(to: url)
            }
        }
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
            if let tests = group.subtests as? [ActionTestMetadata] {
                result += tests.compactMap { $0.summaryRef?.id }
            } else if let subGroups = group.subtests as? [ActionTestSummaryGroup] {
                result += extractTestSummaryIdentifiers(actionTestSummariesGroup: subGroups)
            } else {
                print("Unsupported groups", String(describing: type(of: group.subtests)))
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
