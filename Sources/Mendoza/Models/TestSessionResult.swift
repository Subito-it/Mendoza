//
//  TestSessionResult.swift
//  Mendoza
//
//  Created by Tomas Camin on 26/02/2019.
//

import Foundation

final class TestSessionResult: Codable {
    final class Destination: Codable {
        var username = ""
        var address = ""
        var path = ""
    }
    final class NodeStatistics: Codable {
        var executionTime: TimeInterval
        var totalTests: Int
        
        init(executionTime: TimeInterval, totalTests: Int) {
            self.executionTime = executionTime
            self.totalTests = totalTests
        }
    }
    
    var operationExecutionTime = [String : TimeInterval]()
    var nodes = [String : NodeStatistics]()
    var git: GitStatus?
    var passedTests = [TestCaseResult]()
    var failedTests = [TestCaseResult]()
    var destination = Destination()
    var device = Device.defaultInit()
    var xcResultPath = [String: String]()
    var date = ""
    var startTime: TimeInterval = 0.0
}

extension TestSessionResult: DefaultInitializable {
    static func defaultInit() -> TestSessionResult {
        return TestSessionResult()
    }
}

extension TestSessionResult.Destination: DefaultInitializable {
    static func defaultInit() -> TestSessionResult.Destination {
        return TestSessionResult.Destination()
    }
}

extension TestSessionResult.NodeStatistics: DefaultInitializable {
    static func defaultInit() -> TestSessionResult.NodeStatistics {
        return TestSessionResult.NodeStatistics(executionTime: 0.0, totalTests: 0)
    }
}
