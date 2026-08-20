@testable import mendoza
import XCTest

/// The envelope is the plugin contract: plugins in other languages parse it by hand, so these
/// shapes cannot change silently.
final class PluginEnvelopeTests: XCTestCase {
    private func envelope<Input: DefaultInitializable, Output: DefaultInitializable>(_ plugin: Plugin<Input, Output>, input: Input) throws -> [String: Any] {
        let data = try plugin.makeEnvelope(input: input)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testCarriesInputDataAndDebug() throws {
        let plugin = TearDownPlugin(baseUrl: nil, plugin: .init(data: "{\"channel\":\"#ci\"}", debug: true))
        let envelope = try envelope(plugin, input: TestSessionResult.defaultInit())

        XCTAssertEqual(Set(envelope.keys), ["input", "data", "debug"])
        XCTAssertEqual(envelope["data"] as? String, "{\"channel\":\"#ci\"}")
        XCTAssertEqual(envelope["debug"] as? Bool, true)
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

    func testEventKindIsAStringNotAnOrdinal() throws {
        let plugin = EventPlugin(baseUrl: nil, plugin: .init())
        let envelope = try envelope(plugin, input: EventPluginInput(event: Event(kind: .startTesting, info: [:]), device: Device.defaultInit()))

        let event = try XCTUnwrap((envelope["input"] as? [String: Any])?["event"] as? [String: Any])
        XCTAssertEqual(event["kind"] as? String, "startTesting")
    }
}
