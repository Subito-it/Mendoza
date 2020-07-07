import Foundation

private var _colored = true

extension String {
    func values(pattern: Pattern) -> [String: String] {
        return capturedNamedGroups(with: pattern)
    }

    func beautify(pattern: Pattern, colored: Bool) -> String? {
        _colored = colored

        switch pattern {
        case .analyze:
            return formatAnalyze(pattern: pattern)
        case .compile:
            #if os(Linux)
                return formatCompileLinux(pattern: pattern)
            #else
                fallthrough
            #endif
        case .compileXib,
             .compileStoryboard:
            return formatCompile(pattern: pattern)
        case .compileCommand:
            return formatCompileCommand(pattern: pattern)
        case .buildTarget:
            return formatTargetCommand(command: "Build", pattern: pattern)
        case .analyzeTarget:
            return formatTargetCommand(command: "Analyze", pattern: pattern)
        case .aggregateTarget:
            return formatTargetCommand(command: "Aggregate", pattern: pattern)
        case .cleanTarget:
            return formatTargetCommand(command: "Clean", pattern: pattern)
        case .generateCoverageData,
             .generatedCoverageReport:
            return formatCodeCoverage(pattern: pattern)
        case .generateDsym:
            return formatGenerateDsym(pattern: pattern)
        case .libtool:
            return formatLibtool(pattern: pattern)
        case .linking:
            #if os(Linux)
                return formatLinkingLinux(pattern: pattern)
            #else
                return formatLinking(pattern: pattern)
            #endif
        case .testSuiteStarted,
             .testSuiteStart,
             .parallelTestingStarted,
             .parallelTestingPassed,
             .parallelTestingFailed,
             .parallelTestSuiteStarted:
            return formatTestHeading(pattern: pattern)
        case .failingTest,
             .uiFailingTest,
             .restartingTests,
             .testCasePassed,
             .testCasePending,
             .testCaseMeasured,
             .testsRunCompletion,
             .parallelTestCasePassed,
             .parallelTestCaseAppKitPassed,
             .parallelTestCaseFailed:
            return formatTest(pattern: pattern)
        case .codesign:
            return format(command: "Signing", pattern: pattern)
        case .codesignFramework:
            return formatCodeSignFramework(pattern: pattern)
        case .copyHeader,
             .copyPlist,
             .copyStrings,
             .cpresource,
             .pbxcp:
            return formatCopy(pattern: pattern)
        case .checkDependencies:
            return format(command: "Check Dependencies", pattern: .checkDependencies, arguments: "")
        case .processInfoPlist:
            return formatProcessInfoPlist(pattern: .processInfoPlist)
        case .processPch:
            return formatProcessPch(pattern: pattern)
        case .touch:
            return formatTouch(pattern: pattern)
        case .phaseSuccess:
            let phase = capturedGroups(with: .phaseSuccess)[0].capitalized
            return _colored ? "\(phase) Succeeded".bold.green : "\(phase) Succeeded"
        case .phaseScriptExecution:
            return formatPhaseScriptExecution()
        case .preprocess:
            return format(command: "Preprocessing", pattern: pattern, arguments: "$1")
        case .processPchCommand:
            return formatProcessPchCommand(pattern: pattern)
        case .writeFile:
            return nil
        case .writeAuxiliaryFiles:
            return nil
        case .shellCommand:
            return nil
        case .cleanRemove:
            return formatCleanRemove(pattern: pattern)
        case .executed:
            return nil
        case .testCaseStarted:
            return nil
        case .tiffutil:
            return nil
        case .compileWarning:
            return formatCompileWarning(pattern: pattern)
        case .ldWarning:
            return formatLdWarning(pattern: pattern)
        case .genericWarning:
            return formatWarning(pattern: pattern)
        case .willNotBeCodeSigned:
            return formatWillNotBeCodesignWarning(pattern: pattern)
        case .clangError,
             .fatalError,
             .ldError,
             .podsError,
             .moduleIncludesError:
            return formatError(pattern: pattern)
        case .compileError:
            return formatCompileError(pattern: pattern)
        case .fileMissingError:
            return formatFileMissingError(pattern: pattern)
        case .checkDependenciesErrors:
            return formatError(pattern: pattern)
        case .provisioningProfileRequired:
            return formatError(pattern: pattern)
        case .noCertificate:
            return formatError(pattern: pattern)
        case .cursor:
            return nil
        case .linkerDuplicateSymbolsLocation:
            return nil
        case .linkerDuplicateSymbols:
            return formatLinkerDuplicateSymbolsError(pattern: pattern)
        case .linkerUndefinedSymbolLocation:
            return nil
        case .linkerUndefinedSymbols:
            return formatLinkerUndefinedSymbolsError(pattern: pattern)
        case .symbolReferencedFrom:
            return formatCompleteError()
        case .undefinedSymbolLocation:
            return formatCompleteWarning()
        case .noSpaceOnDevice:
            return nil
        case .checkingForCrashReports:
            return nil
        case .encounteredAnError:
            return nil
        case .encounteredAnSimulatorError:
            return nil
        case .testingFailed:
            return nil
        }
    }

    // MARK: - Private

    private func formatTargetCommand(command: String, pattern: Pattern) -> String {
        let groups = capturedGroups(with: pattern)
        let target = groups[0]
        let project = groups[1]
        let configuration = groups[2]
        return _colored ? "\(command) target \(target) of project \(project) with configuration \(configuration)".bold.cyan : "\(command) target \(target) of project \(project) with configuration \(configuration)"
    }

    private func format(command: String, pattern: Pattern) -> String {
        let groups = capturedGroups(with: pattern)
        let sourceFile = groups[0].lastPathComponent
        return _colored ? command.bold + " " + sourceFile : command + " " + sourceFile
    }

    private func format(command: String, pattern: Pattern, arguments: String) -> String? {
        let template = command + " " + arguments

        guard let formatted =
            try? NSRegularExpression(pattern: pattern.rawValue)
            .stringByReplacingMatches(
                in: self,
                range: NSRange(location: 0, length: count),
                withTemplate: template
            )
        else {
            return nil
        }

        return formatted.components(separatedBy: .whitespacesAndNewlines)
            .flatMap { $0.components(separatedBy: .punctuationCharacters) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func formatAnalyze(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filename = groups[1]
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Analyzing".bold) \(filename)" : "[\(target)] Analyzing \(filename)"
    }

    private func formatCleanRemove(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let directory = groups[0].lastPathComponent
        return _colored ? "\("Cleaning".bold) \(directory)" : "Cleaning \(directory)"
    }

    private func formatCodeSignFramework(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let frameworkPath = groups[0]
        return _colored ? "\("Signing".bold) \(frameworkPath)" : "Signing \(frameworkPath)"
    }

    private func formatProcessPch(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filename = groups[0]
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Processing".bold) \(filename)" : "[\(target)] Processing \(filename)"
    }

    private func formatProcessPchCommand(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        guard let filePath = groups.last else { return nil }
        return _colored ? "\("Preprocessing".bold) \(filePath)" : "Preprocessing \(filePath)"
    }

    private func formatCompileCommand(pattern _: Pattern) -> String? {
        return nil
    }

    private func formatCompile(pattern: Pattern) -> String? {
        return innerFormatCompile(pattern: pattern, fileIndex: 1, targetIndex: 2)
    }

    private func formatCompileLinux(pattern: Pattern) -> String? {
        return innerFormatCompile(pattern: pattern, fileIndex: 1, targetIndex: 0)
    }

    private func innerFormatCompile(pattern: Pattern, fileIndex: Int, targetIndex _: Int) -> String? {
        let groups = capturedGroups(with: pattern)
        let filename = groups[fileIndex]
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Compiling".bold) \(filename)" : "[\(target)] Compiling \(filename)"
    }

    private func formatCopy(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filename = groups[0].lastPathComponent
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Copying".bold) \(filename)" : "[\(target)] Copying \(filename)"
    }

    private func formatGenerateDsym(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let dsym = groups[0]
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Generating".bold) \(dsym)" : "[\(target)] Generating \(dsym)"
    }

    private func formatCodeCoverage(pattern: Pattern) -> String? {
        switch pattern {
        case .generateCoverageData:
            return _colored ? "\("Generating".bold) code coverage data..." : "Generating code coverage data..."
        case .generatedCoverageReport:
            let filePath = capturedGroups(with: pattern)[0]
            return _colored
                ? "\("Generated".bold) code coverage report: \(filePath.italic)"
                : "Generated code coverage report: \(filePath)"
        default:
            return nil
        }
    }

    private func formatLibtool(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filename = groups[0]
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Building library".bold) \(filename)" : "[\(target)] Building library \(filename)"
    }

    private func formatTouch(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filename = groups[1]
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Touching".bold) \(filename)" : "[\(target)] Touching \(filename)"
    }

    private func formatLinking(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filename = groups[0].lastPathComponent
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Linking".bold) \(filename)" : "[\(target)] Linking \(filename)"
    }

    private func formatLinkingLinux(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let target = groups[0]
        return _colored ? "[\(target.cyan)] \("Linking".bold)" : "[\(target)] Linking"
    }

    private func formatPhaseScriptExecution() -> String? {
        let groups = capturedGroups(with: .phaseScriptExecution)
        let phaseName = groups[0]
        // Strip backslashed added by xcodebuild before spaces in the build phase name
        let strippedPhaseName = phaseName.replacingOccurrences(of: "\\ ", with: " ")
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Running script".bold) \(strippedPhaseName)" : "[\(target)] Running script \(strippedPhaseName)"
    }

    private func formatTestHeading(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let testSuite = groups[0]

        switch pattern {
        case .testSuiteStart:
            return _colored ? testSuite.bold : testSuite
        case .testSuiteStarted,
             .parallelTestSuiteStarted:
            let deviceDescription = pattern == .parallelTestSuiteStarted ? " on '\(groups[1])'" : ""
            let heading = "Test Suite \(testSuite) started\(deviceDescription)"
            return _colored ? heading.bold.cyan : heading
        case .parallelTestingStarted:
            return _colored ? bold.cyan : self
        case .parallelTestingPassed:
            return _colored ? bold.green : self
        case .parallelTestingFailed:
            return _colored ? bold.red : self
        default:
            return nil
        }
    }

    private func formatTest(pattern: Pattern) -> String? {
        let indent = "    "
        let groups = capturedGroups(with: pattern)

        switch pattern {
        case .testCasePassed:
            let testCase = groups[1]
            let time = groups[2]
            return _colored ? indent + TestStatus.pass.rawValue.green + " " + testCase + " (\(time.coloredTime()) seconds)" : indent + TestStatus.pass.rawValue + " " + testCase + " (\(time) seconds)"

        case .failingTest:
            let testCase = groups[2]
            let failingReason = groups[3]
            return _colored ? indent + TestStatus.fail.rawValue.red + " " + testCase + ", " + failingReason : indent + TestStatus.fail.rawValue + " " + testCase + ", " + failingReason

        case .uiFailingTest:
            let file = groups[0]
            let failingReason = groups[1]
            return _colored ? indent + TestStatus.fail.rawValue.red + " " + file + ", " + failingReason : indent + TestStatus.fail.rawValue + " " + file + ", " + failingReason

        case .restartingTests:
            return self

        case .testCasePending:
            let testCase = groups[1]
            return _colored ? indent + TestStatus.pending.rawValue.yellow + " " + testCase + " [PENDING]" : indent + TestStatus.pending.rawValue + " " + testCase + " [PENDING]"

        case .testsRunCompletion:
            return nil

        case .testCaseMeasured:
            let testCase = groups[1]
            let time = groups[2]
            return _colored ? indent + TestStatus.measure.rawValue.yellow + " " + testCase + " measured (\(time.coloredTime()) seconds)" : indent + TestStatus.measure.rawValue + " " + testCase + " measured (\(time) seconds)"

        case .parallelTestCasePassed:
            let testCase = groups[1]
            let device = groups[2]
            let time = groups[3]
            return _colored ? indent + TestStatus.pass.rawValue.green + " " + testCase + " on '\(device)' (\(time.coloredTime()) seconds)" : indent + TestStatus.pass.rawValue + " " + testCase + " on '\(device)' (\(time) seconds)"

        case .parallelTestCaseAppKitPassed:
            let testCase = groups[1]
            let time = groups[2]
            return _colored ? indent + TestStatus.pass.rawValue.green + " " + testCase + " (\(time.coloredTime()) seconds)" : indent + TestStatus.pass.rawValue + " " + testCase + " (\(time)) seconds)"

        case .parallelTestCaseFailed:
            let testCase = groups[1]
            let device = groups[2]
            let time = groups[3]
            return _colored ? "    \(TestStatus.fail.rawValue.red) \(testCase) on '\(device)' (\(time.coloredTime()) seconds)" : "    \(TestStatus.fail.rawValue) \(testCase) on '\(device)' (\(time) seconds)"

        default:
            return nil
        }
    }

    private func formatError(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        guard let errorMessage = groups.first else { return nil }
        return _colored ? Symbol.error.rawValue + " " + errorMessage.red : Symbol.asciiError.rawValue + " " + errorMessage
    }

    private func formatCompleteError() -> String? {
        return _colored ? Symbol.error.rawValue + " " + red : Symbol.asciiError.rawValue + " " + self
    }

    private func formatCompileError(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filePath = groups[0]
        let reason = groups[2]

        // Read 2 additional lines to get the error line and cursor position
        let line: String = readLine() ?? ""
        let cursor: String = readLine() ?? ""
        return _colored ?
            """
            \(Symbol.error.rawValue) \(filePath): \(reason.red)
            \(line)
            \(cursor.cyan)
            """
            :
            """
            \(Symbol.asciiError.rawValue) \(filePath): \(reason)
            \(line)
            \(cursor)
            """
    }

    private func formatFileMissingError(pattern: Pattern) -> String {
        let groups = capturedGroups(with: pattern)
        let reason = groups[0]
        let filePath = groups[1]
        return _colored ? "\(Symbol.error.rawValue) \(filePath): \(reason.red)" : "\(Symbol.asciiError.rawValue) \(filePath): \(reason)"
    }

    private func formatWarning(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        guard let warningMessage = groups.first else { return nil }
        return _colored ? Symbol.warning.rawValue + " " + warningMessage.yellow : Symbol.asciiWarning.rawValue + " " + warningMessage
    }

    private func formatCompleteWarning() -> String? {
        return _colored ? Symbol.warning.rawValue + " " + yellow : Symbol.asciiWarning.rawValue + " " + self
    }

    private func formatCompileWarning(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let filePath = groups[0]
        let reason = groups[2]

        // Read 2 additional lines to get the warning line and cursor position
        let line: String = readLine() ?? ""
        let cursor: String = readLine() ?? ""
        return _colored ?
            """
            \(Symbol.warning.rawValue)  \(filePath): \(reason.yellow)
            \(line)
            \(cursor.green)
            """
            :
            """
            \(Symbol.asciiWarning.rawValue)  \(filePath): \(reason)
            \(line)
            \(cursor)
            """
    }

    private func formatLdWarning(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let prefix = groups[0]
        let message = groups[1]
        return _colored ? "\(Symbol.warning.rawValue) \(prefix.yellow)\(message.yellow)" : "\(Symbol.asciiWarning.rawValue) \(prefix)\(message)"
    }

    private func formatProcessInfoPlist(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let plist = groups[1]

        // Xcode 9 output
        if groups.count == 2 {
            return _colored ? "Processing".bold + " " + plist : "Processing" + " " + plist
        }

        // Xcode 10+ output
        guard let target = groups.last else { return nil }
        return _colored ? "[\(target.cyan)] \("Processing".bold) \(plist)" : "[\(target)] \("Processing") \(plist)"
    }

    // TODO: Print symbol and reference location
    private func formatLinkerUndefinedSymbolsError(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let reason = groups[0]
        return _colored ? "\(Symbol.error.rawValue) \(reason.red)" : "\(Symbol.asciiError.rawValue) \(reason)"
    }

    // TODO: Print file path
    private func formatLinkerDuplicateSymbolsError(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        let reason = groups[0]
        return _colored ? "\(Symbol.error.rawValue) \(reason.red)" : "\(Symbol.asciiError.rawValue) \(reason)"
    }

    private func formatWillNotBeCodesignWarning(pattern: Pattern) -> String? {
        let groups = capturedGroups(with: pattern)
        guard let warningMessage = groups.first else { return nil }
        return _colored ? Symbol.warning.rawValue + " " + warningMessage.yellow : Symbol.asciiWarning.rawValue + " " + warningMessage
    }

    private func formatSummary() -> String? {
        return _colored ? bold.green : self
    }

    private func coloredTime() -> String {
        guard let time = Double(self) else { return self }
        if time < 0.025 { return self }
        if time < 0.100 { return _colored ? yellow : self }
        return _colored ? red : self
    }
}
