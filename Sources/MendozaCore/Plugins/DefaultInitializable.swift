//
//  DefaultInitializable.swift
//  Mendoza
//
//  Created by Tomas Camin on 22/01/2019.
//

import Foundation

public protocol DefaultInitializable: Codable {
    static func defaultInit() -> Self
}

extension Array: DefaultInitializable where Element: DefaultInitializable {
    public static func defaultInit() -> [Element] {
        return [Element.defaultInit()]
    }
}

extension Dictionary: DefaultInitializable where Key == String, Value: DefaultInitializable {
    public static func defaultInit() -> [String: Value] {
        return ["": Value.defaultInit()]
    }
}

extension Optional: DefaultInitializable where Wrapped: DefaultInitializable {
    public static func defaultInit() -> Wrapped? {
        return Wrapped.defaultInit()
    }
}

extension DefaultInitializable {
    private static func _defaulInitializableTypes() -> [DefaultInitializable.Type] {
        var result: [DefaultInitializable.Type] = [self]

        let mirror = Mirror(reflecting: defaultInit())
        for (_, value) in mirror.children {
            if let subtype = value.self as? DefaultInitializable {
                result += type(of: subtype)._defaulInitializableTypes()
            } else if let keyValue = value.self as? (key: Any, value: DefaultInitializable) {
                result += type(of: keyValue.value)._defaulInitializableTypes()
            }
        }

        return result
    }

    static func reflections() -> [(subject: String, reflection: String)] {
        var result = [(subject: String, reflection: String)]()

        for mirror in _defaulInitializableTypes().map({ Mirror(reflecting: $0.defaultInit()) }) {
            switch mirror.displayStyle {
            case .some(.struct), .some(.class):
                var entity = [String]()
                if mirror.displayStyle == .some(.struct) {
                    entity.append("struct \(mirror.subjectType): Codable {")
                } else {
                    entity.append("class \(mirror.subjectType): Codable {")
                }

                var structure = [(property: String, type: String)]()
                for (label, value) in mirror.children {
                    if let label = label {
                        structure.append((label, String(describing: type(of: value))))
                    }
                }

                entity += structure.map { "    var \($0.property): \($0.type)" }
                entity.append("}\n")

                result.append((subject: "\(mirror.subjectType)", reflection: entity.joined(separator: "\n")))
            case .some(.enum):
                if mirror.subjectType != PluginVoid.self {
                    fatalError("💣 For enums you should apply the Event.Kind's manual reflection hack")
                }
            case .none:
                if let reflection = mirror.children.filter({ $0.label == "hack" }).compactMap({ $0.value as? String }).first {
                    // HACK: Some types (e.g. enums) cannot be reflected properly
                    result.append((subject: "\(mirror.subjectType)", reflection: reflection))
                }
            default:
                break
            }
        }

        return result
    }
}
