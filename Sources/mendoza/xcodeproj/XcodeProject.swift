//
//  XcodeProject.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/02/2019.
//

import AEXML
import Foundation
import PathKit
import XcodeProj

struct Scheme: CustomStringConvertible {
    var description: String { name }
    var name: String { xcscheme.name }

    private let xcscheme: XCScheme

    init(xcscheme: XCScheme) {
        self.xcscheme = xcscheme
    }
}

class XcodeProject: NSObject {
    enum SDK: String, RawRepresentable {
        case macos = "macosx"
        case ios = "iphoneos"
    }

    enum BuildSystem: String, RawRepresentable {
        case modern
        case original = "Original"
    }

    private let project: XcodeProj
    private let path: PathKit.Path

    private static func projectUrl(from workspaceUrl: URL?) -> URL? {
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

    init(url: URL) throws {
        if url.pathExtension == "xcworkspace", let url = Self.projectUrl(from: url) {
            path = PathKit.Path(url.path)
        } else {
            path = PathKit.Path(url.path)
        }

        project = try XcodeProj(path: path)
    }

    func testingSchemes() -> [Scheme] {
        project.sharedData?.schemes.filter { $0.testAction?.testables.isEmpty == false }.map { Scheme(xcscheme: $0) } ?? []
    }

    func testTargetSourceFilePaths(scheme: String) throws -> [String] {
        let targets = try getTargetsInScheme(scheme)
        return try targets.test.sourceFiles().compactMap(\.path)
    }

    func buildSystem() -> XcodeProject.BuildSystem {
        let buildSystem: WorkspaceSettings.BuildSystem = project.sharedData?.workspaceSettings?.buildSystem ?? .original

        return XcodeProject.BuildSystem(rawValue: buildSystem.rawValue) ?? .modern
    }

    func disableDebugger(schemeName: String) throws {
        let schemePath = XcodeProj.schemePath(path, schemeName: schemeName)

        guard schemePath.exists else { throw Error("Scheme \(schemeName) not found") }
        let schemeUrl = schemePath.url

        let data = try Data(contentsOf: schemeUrl)

        let schemeXml = try AEXMLDocument(xml: data)

        schemeXml.root["TestAction"].attributes["selectedDebuggerIdentifier"] = ""
        schemeXml.root["TestAction"].attributes["selectedLauncherIdentifier"] = "Xcode.IDEFoundation.Launcher.PosixSpawn"

        schemeXml.root["LaunchAction"].attributes["selectedDebuggerIdentifier"] = ""
        schemeXml.root["LaunchAction"].attributes["selectedLauncherIdentifier"] = "Xcode.IDEFoundation.Launcher.PosixSpawn"

        try Data(schemeXml.xml.utf8).write(to: schemeUrl)
    }

    func schemeUrl(name: String) -> URL {
        XcodeProj.schemePath(path, schemeName: name).url
    }

    func buildConfigurations() -> [String] {
        Array(Set(project.pbxproj.buildConfigurations.map(\.name))).sorted()
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

        let testableTargetNames = scheme.testAction?.testables.map(\.buildableReference.blueprintName) ?? []
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

        guard uitestTargets.count == 1 else { throw Error("Expecting 1 uitest target in scheme \(name), found \(uitestTargets.count)") }
        guard buildTargets.count == 1 else { throw Error("Expecting 1 application target in scheme \(name), found \(buildTargets.count)") }

        return (build: buildTargets.first!, test: uitestTargets.first!) // swiftlint:disable:this force_unwrapping
    }

    func getTargetsBundleIdentifiers(scheme: String) throws -> (build: String, test: String) {
        let (buildTarget, uitestTarget) = try getTargetsInScheme(scheme)

        let anyTargetBuildConfigurations: (PBXNativeTarget) throws -> XCBuildConfiguration = { target in
            guard let buildConfiguration = target.buildConfigurationList?.buildConfigurations.first else {
                throw Error("No build configuration found in target \(target.name) in scheme \(scheme)")
            }

            return buildConfiguration
        }

        let uitestBuildConfiguration = try anyTargetBuildConfigurations(uitestTarget)
        let buildBuildConfiguration = try anyTargetBuildConfigurations(buildTarget)

        guard let testBundleIdentifier = uitestBuildConfiguration.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String else { throw Error("Failed to extract bundle identifier from test target") }
        guard let buildBundleIdentifier = buildBuildConfiguration.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String else { throw Error("Failed to extract bundle identifier from build target") }

        return (build: buildBundleIdentifier, test: testBundleIdentifier)
    }

    func getProductNames() -> [String] {
        project.pbxproj.rootObject?.targets.compactMap(\.productName) ?? []
    }

    func getBuildSDK(scheme: String) throws -> SDK {
        let (buildTarget, _) = try getTargetsInScheme(scheme)

        guard let buildProject = project.pbxproj.projects.first(where: { project in project.targets.map(\.name).contains(buildTarget.name) }) else {
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
}
