//
//  Global.swift
//  Mendoza
//
//  Created by Tomas Camin on 07/03/2019.
//

import Foundation

enum Environment {
    static let bundle = "com.subito.mendoza"
    static let defaultConfigurationFilename = "config.json"
    static let temporaryBasePath = "/tmp/mendoza"
    static let htmlTestSummaryFilename = "test_result.html"
    static let jsonTestSummaryFilename = "test_result.json"
    static let jsonGitSummaryFilename = "git_info.json"
    static let htmlRepeatedTestSummaryFilename = "repeated_test_result.html"
    static let jsonRepeatedTestSummaryFilename = "repeated_test_result.json"
    static let jsonSuiteResultFilename = "test_details.json"
    static let htmlExecutionGraphFilename = "test_graph.html"
    static let xcresultFilename = "merged.xcresult"
    static let xcresultFirstUnmergedFilename = "0.xcresult"
    static let coverageFilename = "coverage.json"
    static let coverageSummaryFilename = "coverage-summary.json"
    static let coverageHtmlFilename = "coverage.html"
    static let resultFoldername = "results"
}
