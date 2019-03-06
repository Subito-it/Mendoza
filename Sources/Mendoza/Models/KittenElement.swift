//
//  KittenElement.swift
//  Mendoza
//
//  Created by Tomas Camin on 27/02/2019.
//

import Foundation

struct KittenElement: Codable, Equatable, Hashable {
    let stage: String?
    let accessibility: String?
    let types: [KittenElement]?
    let name: String?
    let kind: String?
    let subElements: [KittenElement]?
    
    enum CodingKeys: String, CodingKey {
        case stage = "key.diagnostic_stage"
        case accessibility = "key.accessibility"
        case types = "key.inheritedtypes"
        case name = "key.name"
        case kind = "key.kind"
        case subElements = "key.substructure"
    }
    
    var isTestMethod: Bool {
        return name?.hasPrefix("test") == true &&
            name?.hasSuffix("()") == true &&
            accessibility != "source.lang.swift.accessibility.private" &&
            kind == "source.lang.swift.decl.function.method.instance"
    }
    
    var isOpenClass: Bool {
        return subElements?.count != 0 &&
            accessibility != "source.lang.swift.accessibility.private" &&
            kind == "source.lang.swift.decl.class"
    }
    
    func conforms(candidates: [KittenElement]) -> Set<String> {
        var items = candidates
        guard var currentInherits = types else { return [] }
        
        var result = Set(currentInherits)
        
        loop: repeat {
            for item in items {
                if currentInherits.map({ $0.name }).contains(item.name) {
                    currentInherits = item.types ?? []
                    result = result.union(currentInherits)
                    items.removeAll { $0 == item }
                    continue loop
                }
            }
            break
        } while true
        
        result = result.union(currentInherits)
        
        return Set(result.compactMap { $0.name })
    }
}
