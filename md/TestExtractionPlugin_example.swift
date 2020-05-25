#!/usr/local/bin/swift-sh
// swiftlint:disable all

import Foundation
import SourceKittenFramework // jpsim/SourceKitten ~> 0.1

// struct TestCase: Codable {
//     var name: String
//     var suite: String
// }
//
// struct TestExtractionInput: Codable {
//     var candidates: Array<URL>
//     var device: Device
// }
//
// struct Device: Codable {
//     var name: String
//     var version: String
// }
//
struct TestExtractionPlugin {
    func handle(_ input: TestExtractionInput, pluginData _: String?) -> [TestCase] {
        do {
            let parser = XCTestFileParser()
            let extractionTestCases = try parser.extractTestCases(
                from: input.candidates,
                baseXCTestCaseClass: input.baseXCTestCaseClass,
                include: input.include,
                exclude: input.exclude
            )

            return extractionTestCases.map { TestCase(name: $0.name, suite: $0.suite) }
        } catch {
            print(error.localizedDescription)
            return []
        }
    }
}

struct ExtractionTestCase {
    let name: String
    let suite: String
    let types: Set<String>
}

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

    var isType: Bool {
        true
        // return kind == "source.lang.swift.decl.function.method.instance" ||
        //        kind == "source.lang.swift.decl.function.protocol.instance"
    }

    var isTestMethod: Bool {
        name?.hasPrefix("test") == true &&
            name?.hasSuffix("()") == true &&
            accessibility != "source.lang.swift.accessibility.private" &&
            kind == "source.lang.swift.decl.function.method.instance"
    }

    var isOpenClass: Bool {
        subElements?.isEmpty != true &&
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

struct XCTestFileParser {
    func extractTestCases(from urls: [URL], baseXCTestCaseClass: input.baseXCTestCaseClass, include: input.include, exclude: input.exclude) throws -> [ExtractionTestCase] {
        var result = [ExtractionTestCase]()

        for url in urls {
            guard let file = File(path: url.path) else { fatalError("File `\(url.path)` does not exists") }

            let structure = try Structure(file: file).description
            guard let structureData = structure.data(using: .utf8) else { fatalError("Failed parsing `\(url.path)` source file") }
            let parsed = try JSONDecoder().decode(KittenElement.self, from: structureData)

            guard let types = parsed.subElements?.filter({ $0.isOpenClass }) else {
                return [] // no testing classes found
            }

            let testClasses = types.filter { $0.conforms(candidates: types).contains(baseXCTestCaseClass) }

            let testCases: [[ExtractionTestCase]] = testClasses.compactMap {
                guard let suite = $0.name,
                    let methods = $0.subElements?.filter({ $0.isTestMethod }) else {
                    return nil
                }

                let testCaseTypes = $0.conforms(candidates: types)
                return methods.map { ExtractionTestCase(name: $0.name!.replacingOccurrences(of: "()", with: ""), suite: suite, types: testCaseTypes) }
            }

            result += testCases.flatMap { $0 }
        }

        return result
    }
}
