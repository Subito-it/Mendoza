//
//  PostCompilationInput.swift
//  Mendoza
//
//  Created by Tomas Camin on 28/01/2019.
//

import Foundation

struct PostCompilationInput: Codable {
    let compilationSucceeded: Bool
    let outputPath: String
}

extension PostCompilationInput: DefaultInitializable {
    static func defaultInit() -> PostCompilationInput {
        PostCompilationInput(compilationSucceeded: false, outputPath: "")
    }
}
