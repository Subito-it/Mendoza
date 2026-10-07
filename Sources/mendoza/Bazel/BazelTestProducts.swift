//
//  BazelTestProducts.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/10/26.
//

import Foundation

/// Lays out Bazel's outputs as `xcodebuild build-for-testing` would: the app, a UI test runner app
/// hosting the test bundle, and the `.xctestrun` describing them.
struct BazelTestProducts {
    static let runnerExecutableName = "XCTRunner"

    private static let platformDeveloperPath = "$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer"
    /// Embedded in the runner when the platform provides them, as Xcode does for the runners it builds.
    private static let runnerFrameworkPaths = [
        "Library/Frameworks/XCTest.framework",
        "Library/Frameworks/Testing.framework",
        "Library/Frameworks/XCUIAutomation.framework",
        "Library/PrivateFrameworks/XCUIAutomation.framework",
        "Library/PrivateFrameworks/XCTestCore.framework",
        "Library/PrivateFrameworks/XCTestSupport.framework",
        "Library/PrivateFrameworks/XCTAutomationSupport.framework",
        "Library/PrivateFrameworks/XCUnit.framework",
        "usr/lib/libXCTestSwiftSupport.dylib",
        "usr/lib/libXCTestBundleInject.dylib"
    ]

    let test: BazelUITest
    let executer: Executer

    static func runnerFileName(test: BazelUITest) -> String {
        "\(test.tests.name)-Runner.app"
    }

    /// Mirrors the identifier Xcode gives the runners it builds.
    static func runnerBundleIdentifier(test: BazelUITest) -> String {
        "\(test.tests.bundleIdentifier).xctrunner"
    }

    func assemble(in productsUrl: URL, architecture: String, profileDataPath: String) throws {
        let runnerUrl = productsUrl.appendingPathComponent(Self.runnerFileName(test: test))

        try copy(test.app, to: productsUrl.appendingPathComponent(test.app.fileName))

        _ = try executer.execute(#"cp -R "\#(Self.platformDeveloperPath)/Library/Xcode/Agents/XCTRunner.app" '\#(runnerUrl.path)'"#)
        _ = try executer.execute("mkdir -p '\(runnerUrl.path)/PlugIns' '\(runnerUrl.path)/Frameworks'")
        try copy(test.tests, to: runnerUrl.appendingPathComponent("PlugIns").appendingPathComponent(test.tests.fileName))
        for path in Self.runnerFrameworkPaths {
            let source = "\(Self.platformDeveloperPath)/\(path)"
            _ = try executer.execute(#"[ ! -e "\#(source)" ] || cp -R "\#(source)" '\#(runnerUrl.path)/Frameworks/'"#)
        }

        // Bazel outputs are read-only: without this the next session could not delete them
        _ = try executer.execute("chmod -R u+w '\(productsUrl.path)'")

        let infoPlistUrl = runnerUrl.appendingPathComponent("Info.plist")
        let infoPlist = try Self.runnerInfoPlist(from: Data(contentsOf: infoPlistUrl), bundleIdentifier: Self.runnerBundleIdentifier(test: test))
        try infoPlist.write(to: infoPlistUrl)

        let xctestrun = Self.xctestrun(test: test, architecture: architecture, profileDataPath: profileDataPath)
        let xctestrunData = try PropertyListSerialization.data(fromPropertyList: xctestrun, format: .xml, options: 0)
        try xctestrunData.write(to: productsUrl.appendingPathComponent("\(test.moduleName)_iphonesimulator.xctestrun"))
    }

    static func runnerInfoPlist(from data: Data, bundleIdentifier: String) throws -> Data {
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let xmlData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let xml = String(decoding: xmlData, as: UTF8.self)
            .replacingOccurrences(of: "$(WRAPPEDPRODUCTNAME)", with: runnerExecutableName)
            .replacingOccurrences(of: "$(WRAPPEDPRODUCTBUNDLEIDENTIFIER)", with: bundleIdentifier)

        let updated = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)
        return try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
    }

    static func xctestrun(test: BazelUITest, architecture: String, profileDataPath: String) -> [String: Any] {
        let appPath = "__TESTROOT__/\(test.app.fileName)"
        let runnerPath = "__TESTROOT__/\(runnerFileName(test: test))"

        let testTarget: [String: Any] = [
            "ProductModuleName": test.moduleName,
            "TestBundlePath": "__TESTHOST__/PlugIns/\(test.tests.fileName)",
            "TestHostPath": runnerPath,
            "TestHostBundleIdentifier": runnerBundleIdentifier(test: test),
            "IsAppHostedTestBundle": true,
            "IsUITestBundle": true,
            "IsXCTRunnerHostedTestBundle": true,
            "UITargetAppPath": appPath,
            "UITargetAppBundleIdentifier": test.app.bundleIdentifier,
            "DependentProductPaths": [appPath, runnerPath, "\(runnerPath)/PlugIns/\(test.tests.fileName)"],
            "TestingEnvironmentVariables": ["DYLD_FRAMEWORK_PATH": "__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks"],
            // Xcode's test plan defaults, which it writes into the .xctestrun it builds. Without them
            // xcodebuild records nothing, leaving failed tests without screen recordings or screenshots.
            "PreferredScreenCaptureFormat": "screenRecording",
            "SystemAttachmentLifetime": "deleteOnSuccess",
            "UserAttachmentLifetime": "deleteOnSuccess",
            // Without it xcodebuild refuses to run with code coverage. It writes the profile data in
            // a subfolder named after the simulator's identifier.
            "ClangProfileDataDirectoryPath": profileDataPath
        ]

        // Without it xcodebuild collects no profile data. FormatVersion 1 takes the singular
        // Architecture and ProductPath, and xcodebuild crashes on the plural forms.
        let coverageBuildable: [String: Any] = [
            "Architecture": architecture,
            "BuildableIdentifier": "\(test.app.name):primary",
            "IncludeInReport": true,
            "IsStatic": false,
            "Name": test.app.fileName,
            "ProductPath": "\(appPath)/\(test.app.executableName)",
            "Toolchains": ["com.apple.dt.toolchain.XcodeDefault"]
        ]

        return [
            test.moduleName: testTarget,
            "__xctestrun_metadata__": ["CodeCoverageBuildableInfos": [coverageBuildable], "FormatVersion": 1]
        ]
    }

    /// Copies a bundle from the execution root, extracting it first when Bazel produced an archive
    /// (`.ipa`, `.zip`) rather than a directory.
    private func copy(_ bundle: BazelBundle, to destinationUrl: URL) throws {
        let sourcePath = test.workspace.executionRootUrl.appendingPathComponent(bundle.archivePath).path

        guard !bundle.archivePath.hasSuffix(bundle.fileName) else {
            _ = try executer.execute("cp -R '\(sourcePath)' '\(destinationUrl.path)'")
            return
        }

        let extractionPath = Path.temp.url.appendingPathComponent(UUID().uuidString).path
        _ = try executer.execute("ditto -x -k '\(sourcePath)' '\(extractionPath)'")
        defer { _ = try? executer.execute("chmod -R u+w '\(extractionPath)'; rm -rf '\(extractionPath)'") }

        let found = try executer.execute("find '\(extractionPath)' -maxdepth 2 -type d -name '\(bundle.fileName)' | head -n 1")
        guard !found.isEmpty else { throw Error("\(bundle.fileName) not found in \(sourcePath)") }

        _ = try executer.execute("cp -R '\(found)' '\(destinationUrl.path)'")
    }
}
