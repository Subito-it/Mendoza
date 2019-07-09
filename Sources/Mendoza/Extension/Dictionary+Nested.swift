//
//  Dictionary+Nested.swift
//  Mendoza
//
//  Created by Tomas Camin on 09/07/2019.
//

import Foundation

extension Dictionary where Key == String {
    func firstKeyPath(where predicate: ((key: String, value: Any)) -> Bool) -> String {
        for (key, value) in self {
            if let arrayValues = value as? [Any] {
                for (index, arrayValue) in arrayValues.enumerated() {
                    let indexedKey = "\(key).\\\(index)"
                    
                    if let subArrayValues = arrayValue as? [Any] {
                        if predicate((indexedKey, subArrayValues)) {
                            return indexedKey
                        }
                    } else if let subDictionary = arrayValue as? [String: Any] {
                        if predicate((indexedKey, arrayValue)) {
                            return indexedKey
                        } else {
                            let subKeyPath = subDictionary.firstKeyPath { k1, v1 in
                                return predicate(("\(indexedKey).\(k1)", v1))
                            }
                            
                            if subKeyPath.count > 0 {
                                return "\(indexedKey).\(subKeyPath)"
                            }
                        }
                    } else {
                        if predicate((indexedKey, value)) {
                            return indexedKey
                        }
                    }
                }
            } else if let subDictionary = value as? [String: Any] {
                if predicate((key, value)) {
                    return key
                } else {
                    let subKeyPath = subDictionary.firstKeyPath { k1, v1 in
                        return predicate(("\(key).\(k1)", v1))
                    }
                    
                    if subKeyPath.count > 0 {
                        return "\(key).\(subKeyPath)"
                    }
                }
            } else {
                if predicate((key, value)) {
                    return key
                }
            }
        }
        
        return ""
    }
}

extension Dictionary where Key == String {
    subscript(keyPath keyPath: String) -> Any? {
        get {
            let segments = keyPath.components(separatedBy: ".")
            guard let head = segments.first, head.isEmpty == false else {
                return self
            }
            
            if segments.count > 1, segments[1].hasPrefix("\\"), let arrayIndex = Int(segments[1].dropFirst()), let array = self[head] as? [Any] {
                if let subDictionary = array[arrayIndex] as? [String: Any] {
                    let subDictionaryKeyPath = segments.dropFirst().dropFirst().joined(separator: ".")
                    return subDictionary[keyPath: subDictionaryKeyPath]
                } else {
                    return array[arrayIndex]
                }
            } else if let subDictionary = self[head] as? [String: Any] {
                return subDictionary[keyPath: segments.dropFirst().joined(separator: ".")]
            } else {
                return self[head]
            }
        }
        set {
            let segments = keyPath.components(separatedBy: ".")
            guard let head = segments.first else {
                return
            }
            
            if segments.count > 1, segments[1].hasPrefix("\\"), let arrayIndex = Int(segments[1].dropFirst()), var array = self[head] as? [Any] {
                if var subDictionary = array[arrayIndex] as? [String: Any] {
                    let subDictionaryKeyPath = segments.dropFirst().dropFirst().joined(separator: ".")
                    switch newValue {
                    case let .some(value):
                        subDictionary[keyPath: subDictionaryKeyPath] = value
                        array[arrayIndex] = subDictionary
                    default:
                        if segments.count == 2 {
                            array.remove(at: arrayIndex)
                        } else {
                            subDictionary[keyPath: subDictionaryKeyPath] = nil
                            array[arrayIndex] = subDictionary
                        }
                    }
                    
                    self[head] = array as? Value
                } else {
                    switch newValue {
                    case let .some(value):
                        array[arrayIndex] = value
                    default:
                        array.remove(at: arrayIndex)
                    }
                    self[head] = array as? Value
                }
            } else if var subDictionary = self[head] as? [String: Any] {
                let subDictionaryKeyPath = segments.dropFirst().joined(separator: ".")
                
                switch newValue {
                case let .some(value):
                    subDictionary[keyPath: subDictionaryKeyPath] = value
                default:
                    if segments.count == 1 {
                        subDictionary.removeValue(forKey: head)
                    } else {
                        subDictionary[keyPath: subDictionaryKeyPath] = nil
                    }
                }
                
                self[head] = subDictionary as? Value
            } else {
                switch newValue {
                case let .some(value):
                    self[head] = value as? Value
                default:
                    removeValue(forKey: head)
                }
            }
        }
    }
}
