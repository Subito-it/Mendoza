//
//  AppInfo.swift
//  Mendoza
//
//  Created by Tomas Camin on 16/06/21.
//

import Foundation

struct AppInfo: Codable {
    let size: UInt64
    let dynamicFrameworkCount: Int
}

extension AppInfo: DefaultInitializable {
    static func defaultInit() -> AppInfo {
        AppInfo(size: 0, dynamicFrameworkCount: 0)
    }
}

extension AppInfo {
    /// Measures the compiled app, or returns empty info when it can't be found.
    static func measure(executer: Executer, buildBundleIdentifier: String) -> AppInfo {
        guard let executablePath = try? findExecutablePath(executer: executer, buildBundleIdentifier: buildBundleIdentifier) else {
            return .defaultInit()
        }

        let appUrl = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        let size = (try? folderSize(appUrl.path)) ?? 0
        let frameworks = try? FileManager.default.contentsOfDirectory(atPath: appUrl.appendingPathComponent("Frameworks").path)

        return AppInfo(size: size, dynamicFrameworkCount: frameworks?.filter { $0.hasSuffix(".framework") }.count ?? 0)
    }

    private static func folderSize(_ path: String) throws -> UInt64 {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)

        var totalSize: UInt64 = 0
        for content in contents {
            do {
                let fullContentPath = path + "/" + content
                let attributes = try FileManager.default.attributesOfItem(atPath: fullContentPath)

                guard let contentType = attributes[.type] as? FileAttributeType else { continue }

                switch contentType {
                case .typeRegular:
                    totalSize += attributes[.size] as? UInt64 ?? 0
                case .typeDirectory:
                    totalSize += try folderSize(fullContentPath)
                default:
                    continue
                }
            } catch _ {
                continue
            }
        }

        return totalSize
    }
}
