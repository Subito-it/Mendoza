@testable import mendoza
import XCTest

final class BazelTests: XCTestCase {
    func testInfoIsParsed() {
        let info = BazelWorkspace.parseInfo("workspace: /path/to/workspace\nexecution_root: /private/var/tmp/_bazel/hash/execroot/_main\n")

        XCTAssertEqual(info["workspace"], "/path/to/workspace")
        XCTAssertEqual(info["execution_root"], "/private/var/tmp/_bazel/hash/execroot/_main")
    }

    func testCQueryTargetsAreKeyedByQueryLabel() throws {
        let output = """
        {"bundle":{"archive":"bazel-out/cfg/bin/App/AppUITests.xctest","bundle_extension":".xctest","bundle_id":"com.example.app.uitests","bundle_name":"AppUITests","executable_name":"AppUITests","platform_type":"ios"},"label":"@@//App:AppUITests"}
        {"label":"@@//App:AppUITestsLib","modules":["AppUITests"]}
        {"label":"@@some_repo//:Dependency","modules":[]}
        """

        let targets = try BazelWorkspace.parseCQuery(output)

        XCTAssertEqual(targets["//App:AppUITests"]?.bundle?.bundleIdentifier, "com.example.app.uitests")
        XCTAssertEqual(targets["//App:AppUITests"]?.bundle?.fileName, "AppUITests.xctest")
        XCTAssertEqual(targets["//App:AppUITestsLib"]?.modules, ["AppUITests"])
        XCTAssertNotNil(targets["@@some_repo//:Dependency"])
    }

    func testSwiftSourcePathsAreWorkspaceRelative() {
        let paths = BazelWorkspace.swiftSourcePaths(fromLabels: [
            "//App:UITests/LoginUITests.swift (null)",
            "@@//:RootUITests.swift (null)",
            "//Modules/Feature:UITests/Nested/FeatureUITests.swift (null)",
            "//App:UITests/Fixture.json (null)",
            "@some_repo//:External.swift (null)"
        ])

        XCTAssertEqual(paths, ["App/UITests/LoginUITests.swift", "RootUITests.swift", "Modules/Feature/UITests/Nested/FeatureUITests.swift"])
    }

    func testRunnerInfoPlistPlaceholdersAreReplaced() throws {
        let template: [String: Any] = [
            "CFBundleExecutable": "$(WRAPPEDPRODUCTNAME)",
            "CFBundleIdentifier": "$(WRAPPEDPRODUCTBUNDLEIDENTIFIER)",
            "CFBundleName": "$(WRAPPEDPRODUCTNAME)",
            "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: template, format: .binary, options: 0)

        let updated = try BazelTestProducts.runnerInfoPlist(from: data, bundleIdentifier: "com.example.app.uitests.xctrunner")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: updated, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "XCTRunner")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.example.app.uitests.xctrunner")
        XCTAssertEqual(plist["CFBundleName"] as? String, "XCTRunner")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "1")
    }

    func testXCTestRunHostsTheTestBundleInTheRunner() throws {
        let xctestrun = BazelTestProducts.xctestrun(test: makeTest(), architecture: "arm64", profileDataPath: "/tmp/mendoza/logs")

        let target = try XCTUnwrap(xctestrun["AppUITests"] as? [String: Any])
        XCTAssertEqual(target["ProductModuleName"] as? String, "AppUITests")
        XCTAssertEqual(target["TestHostPath"] as? String, "__TESTROOT__/AppUITestsBundle-Runner.app")
        XCTAssertEqual(target["TestHostBundleIdentifier"] as? String, "com.example.app.uitests.xctrunner")
        XCTAssertEqual(target["TestBundlePath"] as? String, "__TESTHOST__/PlugIns/AppUITestsBundle.xctest")
        XCTAssertEqual(target["UITargetAppPath"] as? String, "__TESTROOT__/App.app")
        XCTAssertEqual(target["UITargetAppBundleIdentifier"] as? String, "com.example.app")
        XCTAssertEqual(target["ClangProfileDataDirectoryPath"] as? String, "/tmp/mendoza/logs")
        XCTAssertEqual(target["IsUITestBundle"] as? Bool, true)

        let metadata = try XCTUnwrap(xctestrun["__xctestrun_metadata__"] as? [String: Any])
        let buildables = try XCTUnwrap(metadata["CodeCoverageBuildableInfos"] as? [[String: Any]])
        XCTAssertEqual(buildables.first?["ProductPath"] as? String, "__TESTROOT__/App.app/AppExecutable")
        XCTAssertEqual(buildables.first?["Architecture"] as? String, "arm64")
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: xctestrun, format: .xml, options: 0))
    }

    private func makeTest() -> BazelUITest {
        let workspace = BazelWorkspace(url: URL(filePath: "/path/to/workspace"), executionRootUrl: URL(filePath: "/path/to/execroot"), configs: [], executer: LocalExecuter())
        let app = BazelBundle(bundleIdentifier: "com.example.app", name: "App", fileExtension: ".app", executableName: "AppExecutable", archivePath: "bazel-out/cfg/bin/App/App.app", platformType: "ios")
        let tests = BazelBundle(bundleIdentifier: "com.example.app.uitests", name: "AppUITestsBundle", fileExtension: ".xctest", executableName: "AppUITestsBundle", archivePath: "bazel-out/cfg/bin/App/AppUITestsBundle.xctest", platformType: "ios")

        return BazelUITest(workspace: workspace, label: "//App:AppUITests", hostLabel: "//App:App", app: app, tests: tests, moduleName: "AppUITests", sourceFiles: [])
    }
}
