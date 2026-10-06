//
//  BazelUITest.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/10/26.
//

import Foundation

/// An `ios_ui_test` target, described from Bazel's configured build graph.
struct BazelUITest {
    let workspace: BazelWorkspace
    let label: String
    let hostLabel: String
    let app: BazelBundle
    let tests: BazelBundle
    /// Swift module of the test classes, which prefixes their names in xcodebuild's output.
    let moduleName: String
    /// Workspace relative paths of the test sources.
    let sourceFiles: [String]
}

struct BazelBundle: Decodable, Equatable {
    let bundleIdentifier: String
    let name: String
    let fileExtension: String
    let executableName: String
    /// Path of the bundle, or of the archive containing it, relative to the execution root.
    let archivePath: String
    let platformType: String

    var fileName: String {
        name + fileExtension
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_id"
        case name = "bundle_name"
        case fileExtension = "bundle_extension"
        case executableName = "executable_name"
        case archivePath = "archive"
        case platformType = "platform_type"
    }
}
