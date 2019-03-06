//
//  Node+Extension.swift
//  Mendoza
//
//  Created by Tomas Camin on 31/01/2019.
//

import Foundation

extension Sequence where Element == Node {
    /// Return a list of unique nodes by filtering out localhost
    /// if it's already contained among remote nodes
    ///
    /// - Returns: array of unique nodes
    func unique() -> [Element] {
        var ret = [Element]()
        var localAdded = false
        
        for node in self {
            guard !ret.contains(node) else { continue }
            
            switch AddressType(node: node) {
            case .local where localAdded == false:
                ret.append(node)
                localAdded = true
            case .remote:
                ret.append(node)
            case .local:
                break
            }
        }
        
        return ret
    }

    /// Returns remote nodes only
    ///
    /// - Returns: array of remote nodes
    func remote() -> [Element] {
        return filter { AddressType(node: $0) == .remote }
    }
}
