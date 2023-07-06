//
//  XCTestFileParser.swift
//  Mendoza
//
//  Created by Tomas Camin on 24/01/2019.
//

import Foundation
import SourceKittenFramework

struct XCTestFileParser {
    func extractTestCases(from urls: [URL]) throws -> [TestCase] {
        var result = [TestCase]()

        for url in urls {
            guard let file = File(path: url.path) else { throw Error("File `\(url.path)` does not exists") }

            let structure = try Structure(file: file).description
            guard let structureData = structure.data(using: .utf8) else { throw Error("Failed parsing `\(url.path)` source file") }
            let parsed = try JSONDecoder().decode(KittenElement.self, from: structureData)

            guard let visibleClasses = parsed.subElements?.filter(\.isOpenClass) else {
                return [] // no testing classes found
            }

            let testClasses = visibleClasses.filter { $0.conforms(candidates: visibleClasses).contains("XCTestCase") }

            let testCases: [[TestCase]] = testClasses.compactMap {
                guard let suite = $0.name,
                      let methods = $0.subElements?.filter(\.isTestMethod)
                else {
                    return nil
                }

                return methods.map { TestCase(name: $0.name!.replacingOccurrences(of: "()", with: ""), suite: suite) } // swiftlint:disable:this force_unwrapping
            }

            result += testCases.flatMap { $0 }
        }

        return result
    }
}
