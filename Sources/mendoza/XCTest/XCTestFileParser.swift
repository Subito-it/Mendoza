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
        // Parse each source file with sourcekitd exactly once; the inheritance-collection
        // passes below only need the decoded structures, not repeated re-parses.
        let allVisibleClasses: [[KittenElement]] = try urls.map { url in
            guard let file = File(path: url.path) else { throw Error("File `\(url.path)` does not exists") }

            let structure = try Structure(file: file).description
            guard let structureData = structure.data(using: .utf8) else { throw Error("Failed parsing `\(url.path)` source file") }
            let parsed = try JSONDecoder().decode(KittenElement.self, from: structureData)

            return parsed.subElements?.filter(\.isOpenClass) ?? []
        }

        var testClasses = [KittenElement(stage: nil, accessibility: nil, types: nil, name: "XCTestCase", kind: nil, subElements: nil, attributes: nil, typeName: nil)]
        var testClassNames = Set(testClasses.compactMap(\.name))
        for _ in 0 ..< 5 { // Repeat to collect class inheritance
            for visibleClasses in allVisibleClasses {
                let matches = visibleClasses.filter { visibleClass in
                    // `conforms` depends only on the class and its file's candidates, so compute it
                    // once per class instead of once per already-collected test class.
                    !visibleClass.conforms(candidates: visibleClasses).isDisjoint(with: testClassNames)
                }
                for match in matches where !(match.name.map(testClassNames.contains) ?? false) {
                    testClasses.append(match)
                    if let name = match.name { testClassNames.insert(name) }
                }
            }
        }

        let testCases: [[TestCase]] = testClasses.compactMap {
            guard let suite = $0.name,
                  let methods = $0.subElements?.filter(\.isTestMethod)
            else {
                return nil
            }

            return methods.map { TestCase(name: $0.name!.replacingOccurrences(of: "()", with: ""), suite: suite) } // swiftlint:disable:this force_unwrapping
        }

        let result = testCases.flatMap { $0 }.sorted(by: { $0.testIdentifier < $1.testIdentifier })

        return result
    }
}
