//
//  XcodeProject.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/02/2019.
//

import Foundation
import PathKit
import TSCBasic
import XcodeProj

public struct Scheme: CustomStringConvertible {
    public var description: String { return name }
    public var name: String { return xcscheme.name }

    private let xcscheme: XCScheme

    init(xcscheme: XCScheme) {
        self.xcscheme = xcscheme
    }
}

public class XcodeProject: NSObject {
    public enum SDK: String, RawRepresentable {
        case macos = "macosx"
        case ios = "iphoneos"

        public var value: String {
            switch self {
            case .macos: return "macosx"
            case .ios:   return "iphonesimulator"
            }
        }
    }

    enum BuildSystem: String, RawRepresentable {
        case modern
        case original = "Original"
    }

    private let project: XcodeProj
    private let path: PathKit.Path

    public static func projectUrl(from workspaceUrl: URL?) -> URL? {
        guard let path = workspaceUrl?.path else { return nil }

        guard let got = try? XCWorkspace(pathString: path) else { return nil }
        for child in got.data.children {
            switch child {
            case let .file(ref):
                return workspaceUrl?.deletingLastPathComponent().appendingPathComponent(ref.location.path)
            case let .group(ref):
                fatalError("💣 Unhandled ref \(ref)")
            }
        }

        fatalError("💣 Unhandled")
    }

    public init(url: URL) throws {
        path = PathKit.Path(url.path)
        project = try XcodeProj(path: path)
    }

    public func testingSchemes() -> [Scheme] {
        project.sharedData?.schemes.filter { $0.testAction?.testables.isEmpty == false }.map { Scheme(xcscheme: $0) } ?? []
    }

    public func testTargetSourceFilePaths(scheme: String) throws -> [String] {
        let targets = try getTargetsInScheme(scheme)
        return try targets.test.sourceFiles().compactMap { $0.path }
    }

    func buildSystem() -> XcodeProject.BuildSystem {
        let buildSystem: WorkspaceSettings.BuildSystem = project.sharedData?.workspaceSettings?.buildSystem ?? .original

        return XcodeProject.BuildSystem(rawValue: buildSystem.rawValue) ?? .modern
    }

    func disableDebugger(schemeName: String) throws {
        guard let scheme = xcscheme(name: schemeName) else {
            throw Error("Scheme \(schemeName) not found")
        }

        scheme.testAction?.selectedDebuggerIdentifier = ""
        scheme.testAction?.selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.PosixSpawn"

        scheme.launchAction?.selectedDebuggerIdentifier = ""
        scheme.launchAction?.selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.PosixSpawn"

        try scheme.write(path: XcodeProj.schemePath(path, schemeName: scheme.name), override: true)
    }

    public func schemeUrl(name: String) -> URL {
        XcodeProj.schemePath(path, schemeName: name).url
    }

    public func buildConfigurations() -> [String] {
        Array(Set(project.pbxproj.buildConfigurations.map { $0.name })).sorted()
    }

    func backupScheme(name: String, baseUrl _: URL) throws -> URL {
        let url = schemeUrl(name: name)

        let destinationUrl = Path.temp.url.appendingPathComponent(url.lastPathComponent)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationUrl)
        try fileManager.copyItem(at: url, to: destinationUrl)
        return destinationUrl
    }

    func restoreScheme(name: String, with backupUrl: URL) throws {
        let url = schemeUrl(name: name)

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        try fileManager.copyItem(at: backupUrl, to: url)
        try fileManager.removeItem(at: backupUrl)
    }

    func xcscheme(name: String) -> XCScheme? {
        project.sharedData?.schemes.first(where: { $0.name == name })
    }

    func getTargetsInScheme(_ name: String) throws -> (build: PBXNativeTarget, test: PBXNativeTarget) {
        guard let scheme = xcscheme(name: name) else { throw Error("Scheme \(name) not found!") }

        guard let runTargetName = scheme.launchAction?.runnable?.buildableReference.blueprintName else {
            throw Error("Expecting 1 run target in scheme \(name). Check that you have an executable selected in the info section of the run settings in the selected scheme.")
        }

        let testableTargetNames = scheme.testAction?.testables.map { $0.buildableReference.blueprintName } ?? []
        guard testableTargetNames.count == 1 else {
            throw Error("Expecting 1 testing target in scheme \(name). Check that you have an executable selected in the info section of the run settings in the selected scheme.")
        }

        let targets = project.pbxproj.nativeTargets

        let schemeTargets = [runTargetName, testableTargetNames[0]]
        let targetsByBundle: (PBXProductType) -> [PBXNativeTarget] = { type in
            targets.filter { $0.productType == type }.filter { schemeTargets.contains($0.name) }
        }

        let uitestTargets = targetsByBundle(.uiTestBundle)
        let buildTargets = targetsByBundle(.application)

        guard uitestTargets.count == 1 else {
            throw Error("Expecting 1 uitest target in scheme \(name), found \(uitestTargets.count)")
        }

        guard buildTargets.count == 1 else {
            throw Error("Expecting 1 application target in scheme \(name), found \(buildTargets.count)")
        }

        return (build: buildTargets.first!, test: uitestTargets.first!) // swiftlint:disable:this force_unwrapping
    }

    public func getTargetsBundleIdentifiers(for schemeName: String) throws -> (build: String, test: String) {
        let (buildTarget, uitestTarget) = try getTargetsInScheme(schemeName)

        let anyTargetBuildConfigurations: (PBXNativeTarget) throws -> XCBuildConfiguration = { target in
            guard let buildConfiguration = target.buildConfigurationList?.buildConfigurations.first else {
                throw Error("No build configuration found in target \(target.name) in scheme \(schemeName)")
            }

            return buildConfiguration
        }

        let uitestBuildConfiguration = try anyTargetBuildConfigurations(uitestTarget)
        let buildBuildConfiguration = try anyTargetBuildConfigurations(buildTarget)

        var testBundleIdentifier: String
        var buildBundleIdentifier: String

        let productIdentifier = "PRODUCT_BUNDLE_IDENTIFIER"

        if let testIdentifier = uitestBuildConfiguration.buildSettings[productIdentifier] as? String {
            testBundleIdentifier = testIdentifier
        } else {
            testBundleIdentifier = try getBuildSetting(configuration: schemeName, key: productIdentifier)
        }

        if let buildIdentifier = buildBuildConfiguration.buildSettings[productIdentifier] as? String {
            buildBundleIdentifier = buildIdentifier
        } else {
            buildBundleIdentifier = try getBuildSetting(configuration: schemeName, key: productIdentifier)
        }

        guard !testBundleIdentifier.isEmpty else {
            throw Error("Failed to extract bundle identifier from test target")
        }

        guard !buildBundleIdentifier.isEmpty else {
            throw Error("Failed to extract bundle identifier from build target")
        }

        return (build: buildBundleIdentifier, test: testBundleIdentifier)
    }

    public func getBuildSDK(for schemeName: String) throws -> SDK {
        let (buildTarget, _) = try getTargetsInScheme(schemeName)

        guard let buildProject = project.pbxproj.projects.first(where: { project in project.targets.map { $0.name }.contains(buildTarget.name) }) else {
            throw Error("Failed to extract build project")
        }

        guard let buildConfiguration = buildProject.buildConfigurationList?.buildConfigurations.first else {
            throw Error("No build configuration found in \(buildProject.uuid)")
        }

        guard let rawSdk = buildConfiguration.buildSettings["SDKROOT"] as? String else {
            throw Error("No SDKROOT in \(buildConfiguration.uuid)")
        }

        guard let sdk = SDK(rawValue: rawSdk) else {
            throw Error("Unsupported SDKROOT \(rawSdk). Expecting either iphoneos or macosx")
        }

        return sdk
    }

    func getBuildSetting(configuration: String, key: String) throws -> String {
        return try (extractBuildSettings(configuration: configuration).filter { $0.key == key }.first?.value ?? "")

    }
    private func extractBuildSettings(configuration: String) throws -> [BuildSetting] {
        let arguments: [String] = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "-project",
            path.url.absoluteString.replacingOccurrences(of: "file://", with: ""),
            "-showBuildSettings",
            "-configuration",
            configuration,
        ]

        print("Running Command:")
        print(arguments.joined(separator: " "))

        let rawBuildSettings = try TSCBasic.Process.checkNonZeroExit(arguments: arguments)

        return rawBuildSettings.components(separatedBy: .newlines)
            .map { key in key.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { $0.count == 2 }
            .compactMap { BuildSetting(key: $0[0], value: $0[1]) }
    }
}

struct BuildSetting {
    let key: String
    let value: String
}
