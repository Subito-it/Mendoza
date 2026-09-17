import CachiKit
import Foundation

/// Compatibility boundary for CachiKit's typed models. Xcode 27 omits `_values` on empty arrays.
/// Normalize only that representation; malformed values and unrelated missing fields still fail decoding.
final class XcResultReader {
    private let readObject: (String?) throws -> Data

    init(url: URL, readObject: ((String?) throws -> Data)? = nil) {
        if let readObject {
            self.readObject = readObject
        } else {
            let executer = LocalExecuter()
            var legacyParameter: String?
            self.readObject = { identifier in
                if legacyParameter == nil {
                    let version = try executer.execute("xcrun xcresulttool version")
                    legacyParameter = version.contains("version 22") ? "" : " --legacy"
                }
                func quote(_ value: String) -> String {
                    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
                }
                let selection = identifier.map { " --id " + quote($0) } ?? ""
                let output = try executer.execute("xcrun xcresulttool get --format json --path " + quote(url.path) + selection + (legacyParameter ?? ""))
                return Data(output.utf8)
            }
        }
    }

    func decode<T: Decodable>(_ type: T.Type, identifier: String? = nil) throws -> T {
        let object = try JSONSerialization.jsonObject(with: readObject(identifier))
        let normalized = try JSONSerialization.data(withJSONObject: Self.normalizeEmptyArrays(object))
        return try JSONDecoder().decode(type, from: normalized)
    }

    static func normalizeEmptyArrays(_ object: Any) -> Any {
        if var dictionary = object as? [String: Any] {
            if let type = dictionary["_type"] as? [String: Any], type["_name"] as? String == "Array", dictionary["_values"] == nil {
                dictionary["_values"] = [Any]()
            }
            return dictionary.mapValues(normalizeEmptyArrays)
        }
        if let values = object as? [Any] {
            return values.map(normalizeEmptyArrays)
        }
        return object
    }
}
