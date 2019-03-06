//
//  URL+Extension.swift
//  Mendoza
//
//  Created by Tomas Camin on 23/02/2019.
//
// https://stackoverflow.com/a/48360631/574449

import Foundation

extension URL {
    func relativePath(from base: URL) -> String? {
        guard self.isFileURL && base.isFileURL else { return nil }
        
        // Remove/replace "." and "..", make paths absolute:
        let destComponents = self.standardized.pathComponents
        let baseComponents = base.standardized.pathComponents
        
        // Find number of common path components:
        var i = 0
        while i < destComponents.count && i < baseComponents.count
            && destComponents[i] == baseComponents[i] {
                i += 1
        }
        
        // Build relative path:
        var relComponents = Array(repeating: "..", count: baseComponents.count - i)
        relComponents.append(contentsOf: destComponents[i...])
        return relComponents.joined(separator: "/")
    }
}
