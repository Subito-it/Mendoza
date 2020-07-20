//
//  XCTestFileParser.swift
//  Mendoza
//
//  Created by Tomas Camin on 24/01/2019.
//

import Foundation
import Slang
import SourceKittenFramework

struct XCTestFileParser {
    func extractTestCases(from urls: [URL], baseXCTestCaseClass: String, include: [String], exclude: [String]) throws -> [TestCase] {
        var result = [TestCase]()

        for url in urls {
            guard let file = File(url) else {
                throw Error("File `\(url.path)` does not exists")
            }

            let disassembly = try Disassembly(file)
            let query = disassembly.query.structure

            let testClasses = query.descendants(where: { $0.conformsTo(class: baseXCTestCaseClass) })

            let output: [[TestCase]] = testClasses.compactMap { baseTestClass in
                guard let testClass = baseTestClass.one else {
                    return nil
                }

                let testMethods = baseTestClass.children(where: { $0.functionName(startsWith: "test") })

                return testMethods.compactMap { function in
                    guard let testMethod = function.one else {
                        return nil
                    }

                    let testCaseIDs = function
                        .children(where: { $0.closureName(contains: "report") })
                        .children(where: { $0.argumentName(contains: "testCases") })
                        .one?.bodyCollection ?? []

                    let testTags = function
                        .children(where: { $0.closureName(contains: "tags") })
                        .children(where: { $0.argumentName(contains: "testTags") })
                        .one?.bodyCollection ?? []

                    return TestCase(name: testMethod.name, suite: testClass.name, tags: testTags, testCaseIDs: testCaseIDs)
                }
            }

            result += output.flatMap { $0 }
        }

        return filter(testCases: result, include: include, exclude: exclude)
    }

    func filter(testCases: [TestCase], include: [String], exclude: [String]) -> [TestCase] {
        return testCases.filter { testcase in
            var filterTestCase = include.isEmpty ? true : false

            var testcaseAttributes = [String]()

            testcaseAttributes.append(contentsOf: testcase.tags)
            testcaseAttributes.append(contentsOf: testcase.testCaseIDs)
            testcaseAttributes.append(testcase.suite)
            testcaseAttributes.append(testcase.name)
            testcaseAttributes.append(testcase.testIdentifier)

            testcaseAttributes = testcaseAttributes.compactMap { $0.lowercased() }

            if !include.isEmpty {
                filterTestCase = include.contains(where: { testcaseAttributes.contains($0) })
            }

            if !exclude.isEmpty, filterTestCase == true {
                filterTestCase = !exclude.contains(where: { testcaseAttributes.contains($0) })
            }

            return filterTestCase
        }
    }
}
