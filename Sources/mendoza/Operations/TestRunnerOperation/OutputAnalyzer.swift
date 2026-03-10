//
//  OutputAnalyzer.swift
//  Mendoza
//
//  Created by tomas.camin on 26/02/2026.
//

import Foundation

/// Analyzes xcodebuild output to detect various failure modes
struct OutputAnalyzer {
    struct FailureAnalysis {
        var missingAccessibilityPermission: Bool = false
        var failedPreflightChecks: Bool = false
        var failedBootstrapping: Bool = false
        var failedLoadingAccessibility: Bool = false
        var damagedBuild: Bool = false

        var requiresSimulatorReset: Bool {
            failedPreflightChecks || failedLoadingAccessibility
        }

        var requiresBootstrapWait: Bool {
            failedBootstrapping
        }
    }

    /// Analyze xcodebuild output for known failure patterns
    func analyze(_ output: String) -> FailureAnalysis {
        var analysis = FailureAnalysis()

        analysis.missingAccessibilityPermission = output.contains("does not have permission to use Accessibility")
        analysis.failedPreflightChecks = output.contains("Application failed preflight checks")
        analysis.failedBootstrapping = output.contains("Test runner exited before starting test execution")
        analysis.failedLoadingAccessibility = output.contains("has not loaded accessibility")
        analysis.damagedBuild = output.contains("The application may be damaged or incomplete")

        return analysis
    }

    /// Assert that accessibility permissions are granted, throws if not
    func assertAccessibilityPermissions(in output: String) throws {
        if output.contains("does not have permission to use Accessibility") {
            throw Error("Unable to run UI Tests because Xcode Helper does not have permission to use Accessibility. To enable UI testing, go to the Security & Privacy pane in System Preferences, select the Privacy tab, then select Accessibility, and add Xcode Helper to the list of applications allowed to use Accessibility")
        }
    }
}
