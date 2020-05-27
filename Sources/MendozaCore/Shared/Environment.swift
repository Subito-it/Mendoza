//
//  Global.swift
//  Mendoza
//
//  Created by tomas on 07/03/2019.
//

import Foundation

public enum Environment {
    public static let bundle = "com.subito.mendoza"
    public static let defaultConfigurationFilename = "mendoza.json"
    public static let ramDiskName = "mendoza"
    public static let temporaryBasePath = "/tmp/mendoza"
    public static let htmlTestSummaryFilename = "test_result.html"
    public static let jsonTestSummaryFilename = "test_result.json"
    public static let jsonGitSummaryFilename = "git_info.json"
    public static let htmlRepeatedTestSummaryFilename = "repeated_test_result.html"
    public static let jsonRepeatedTestSummaryFilename = "repeated_test_result.json"
    public static let suiteResultFilename = "test_details.json"
    public static let xcresultFilename = "merged.xcresult"
    public static let pluginFolder = ".mendoza"
}
