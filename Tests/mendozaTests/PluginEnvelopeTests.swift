@testable import mendoza
import XCTest

/// The envelope is the plugin contract: plugins in other languages parse it by hand, so these
/// shapes cannot change silently.
final class PluginEnvelopeTests: XCTestCase {
    private func envelope<Input: DefaultInitializable, Output: DefaultInitializable>(_ plugin: Plugin<Input, Output>, input: Input) throws -> [String: Any] {
        let data = try plugin.makeEnvelope(input: input)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testCarriesInputAndData() throws {
        let plugin = TearDownPlugin(baseUrl: nil, plugin: .init(data: "{\"channel\":\"#ci\"}"))
        let envelope = try envelope(plugin, input: TestSessionResult.defaultInit())

        XCTAssertEqual(Set(envelope.keys), ["input", "data"])
        XCTAssertEqual(envelope["data"] as? String, "{\"channel\":\"#ci\"}")
        XCTAssertNotNil(envelope["input"] as? [String: Any])
    }

    /// `data` must be null rather than "" when unset: the usual `payload["data"] || "{}"`
    /// fallback does not trigger for an empty string, which then fails to parse as JSON.
    func testUnsetDataIsNullAndPresent() throws {
        let plugin = TearDownPlugin(baseUrl: nil, plugin: .init())
        let envelope = try envelope(plugin, input: TestSessionResult.defaultInit())

        XCTAssertTrue(envelope.keys.contains("data"))
        XCTAssertNil(envelope["data"] as? String)
        XCTAssertTrue(envelope["data"] is NSNull)
    }

    /// Plugins taking no input still get an `input` key, as an empty object.
    func testVoidInputEncodesAsEmptyObject() throws {
        let plugin = PreCompilationPlugin(baseUrl: nil, plugin: .init())
        let envelope = try envelope(plugin, input: PluginVoid.void)

        XCTAssertEqual(try XCTUnwrap(envelope["input"] as? [String: Any]).count, 0)
    }

    /// --plugin_replay_path exists so envelopes survive somewhere of the caller's choosing: the
    /// default lands in the session logs, which the next session wipes.
    func testEnvelopeIsWrittenToTheReplayPath() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let plugins = root.appendingPathComponent("plugins")
        let replay = root.appendingPathComponent("replay")
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = plugins.appendingPathComponent("PreCompilationPlugin")
        try "#!/bin/sh\ncat > /dev/null\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let plugin = PreCompilationPlugin(baseUrl: plugins, plugin: .init(replayPath: replay.path))
        _ = try plugin.run(input: PluginVoid.void)

        let written = try FileManager.default.contentsOfDirectory(atPath: replay.path)
        XCTAssertEqual(written.count, 1)
        let name = try XCTUnwrap(written.first)
        XCTAssertTrue(name.hasPrefix("PreCompilationPlugin."), name)
        XCTAssertTrue(name.hasSuffix(".json"), name)

        let attributes = try FileManager.default.attributesOfItem(atPath: replay.appendingPathComponent(name).path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testEventKindIsAStringNotAnOrdinal() throws {
        let plugin = EventPlugin(baseUrl: nil, plugin: .init())
        let envelope = try envelope(plugin, input: EventPluginInput(event: Event(kind: .startTesting, info: [:]), device: Device.defaultInit()))

        let event = try XCTUnwrap((envelope["input"] as? [String: Any])?["event"] as? [String: Any])
        XCTAssertEqual(event["kind"] as? String, "startTesting")
    }
}
