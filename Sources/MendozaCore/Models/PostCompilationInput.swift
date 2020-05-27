//
//  PostCompilationInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 28/01/2019.
//

import Foundation

public struct PostCompilationInput: Codable {
    let compilationSucceeded: Bool
}

extension PostCompilationInput: DefaultInitializable {
    public static func defaultInit() -> PostCompilationInput {
        return PostCompilationInput(compilationSucceeded: false)
    }
}
