@testable import mendoza
import PathKit
import XcodeProj
import XCTest

final class XcodeProjectTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSingleUITestBundleIsSelected() throws {
        let project = try makeProject(testables: [("AppUITests", .uiTestBundle)])

        let targets = try project.getTargetsInScheme("App")

        XCTAssertEqual(targets.build.name, "App")
        XCTAssertEqual(targets.test.name, "AppUITests")
    }

    func testUnitTestBundleInSchemeIsIgnored() throws {
        let project = try makeProject(testables: [("AppTests", .unitTestBundle), ("AppUITests", .uiTestBundle)])

        let targets = try project.getTargetsInScheme("App")

        XCTAssertEqual(targets.build.name, "App")
        XCTAssertEqual(targets.test.name, "AppUITests")
    }

    func testMultipleUITestBundlesThrow() throws {
        let project = try makeProject(testables: [("AppUITests", .uiTestBundle), ("OtherUITests", .uiTestBundle)])

        XCTAssertThrowsError(try project.getTargetsInScheme("App"))
    }

    func testSchemeWithoutUITestBundleThrows() throws {
        let project = try makeProject(testables: [("AppTests", .unitTestBundle)])

        XCTAssertThrowsError(try project.getTargetsInScheme("App"))
    }

    func testBuildSDKIsReadFromProject() throws {
        let project = try makeProject(projectSettings: ["SDKROOT": "macosx"])

        XCTAssertEqual(try project.getBuildSDK(scheme: "App"), .macos)
    }

    func testBuildSDKIsReadFromAppTarget() throws {
        let project = try makeProject(appSettings: ["SDKROOT": "iphoneos"])

        XCTAssertEqual(try project.getBuildSDK(scheme: "App"), .ios)
    }

    func testAppTargetBuildSDKOverridesProject() throws {
        let project = try makeProject(projectSettings: ["SDKROOT": "macosx"], appSettings: ["SDKROOT": "iphoneos"])

        XCTAssertEqual(try project.getBuildSDK(scheme: "App"), .ios)
    }

    func testMissingBuildSDKThrows() throws {
        let project = try makeProject()

        XCTAssertThrowsError(try project.getBuildSDK(scheme: "App"))
    }

    private func makeProject(testables: [(name: String, productType: PBXProductType)] = [("AppUITests", .uiTestBundle)],
                             projectSettings: BuildSettings = [:],
                             appSettings: BuildSettings = [:]) throws -> XcodeProject {
        let appConfiguration = XCBuildConfiguration(name: "Debug", buildSettings: appSettings)
        let appConfigurationList = XCConfigurationList(buildConfigurations: [appConfiguration])
        let app = PBXNativeTarget(name: "App", buildConfigurationList: appConfigurationList, productType: .application)
        let testTargets = testables.map { PBXNativeTarget(name: $0.name, productType: $0.productType) }

        let projectConfiguration = XCBuildConfiguration(name: "Debug", buildSettings: projectSettings)
        let configurationList = XCConfigurationList(buildConfigurations: [projectConfiguration])
        let mainGroup = PBXGroup()
        let rootObject = PBXProject(name: "App", buildConfigurationList: configurationList, compatibilityVersion: "Xcode 14.0", mainGroup: mainGroup, targets: [app] + testTargets)
        let objects: [PBXObject] = [projectConfiguration, configurationList, appConfiguration, appConfigurationList, mainGroup, rootObject, app] + testTargets
        let pbxproj = PBXProj(rootObject: rootObject, objects: objects)

        let reference: (PBXNativeTarget) -> XCScheme.BuildableReference = { target in
            XCScheme.BuildableReference(referencedContainer: "container:App.xcodeproj", blueprint: target, buildableName: target.name, blueprintName: target.name)
        }
        let testAction = XCScheme.TestAction(buildConfiguration: "Debug", macroExpansion: nil, testables: testTargets.map { XCScheme.TestableReference(skipped: false, buildableReference: reference($0)) })
        let launchAction = XCScheme.LaunchAction(runnable: XCScheme.BuildableProductRunnable(buildableReference: reference(app)), buildConfiguration: "Debug")
        let scheme = XCScheme(name: "App", lastUpgradeVersion: nil, version: nil, testAction: testAction, launchAction: launchAction)

        let path = Path(directory.appendingPathComponent("App.xcodeproj").path)
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj, sharedData: XCSharedData(schemes: [scheme])).write(path: path)

        return try XcodeProject(url: path.url)
    }
}
