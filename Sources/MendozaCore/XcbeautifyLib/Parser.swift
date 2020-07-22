public class Parser {
    public init() {}

    public var summary: TestSummary?

    public func parse(line: String, colored: Bool = true) -> (line: String?, outputType: XCBOutputType, pattern: Pattern, value: [String: String]) {
        var pattern: Pattern
        var outputType = XCBOutputType.undefined

        switch line {
        case Matcher.analyzeMatcher:
            outputType = XCBOutputType.task
            pattern = .analyze

        case Matcher.buildTargetMatcher:
            outputType = XCBOutputType.task
            pattern = .buildTarget

        case Matcher.aggregateTargetMatcher:
            outputType = XCBOutputType.task
            pattern = .aggregateTarget

        case Matcher.analyzeTargetMatcher:
            outputType = XCBOutputType.task
            pattern = .analyzeTarget

        case Matcher.checkDependenciesMatcher:
            outputType = XCBOutputType.task
            pattern = .checkDependencies

        case Matcher.cleanRemoveMatcher:
            outputType = XCBOutputType.task
            pattern = .cleanRemove

        case Matcher.cleanTargetMatcher:
            outputType = XCBOutputType.task
            pattern = .cleanTarget

        case Matcher.codesignFrameworkMatcher:
            outputType = XCBOutputType.task
            pattern = .codesignFramework

        case Matcher.codesignMatcher:
            outputType = XCBOutputType.task
            pattern = .codesign

        case Matcher.compileMatcher:
            outputType = XCBOutputType.task
            pattern = .compile

        case Matcher.compileCommandMatcher:
            outputType = XCBOutputType.task
            pattern = .compileCommand

        case Matcher.compileXibMatcher:
            outputType = XCBOutputType.task
            pattern = .compileXib

        case Matcher.compileStoryboardMatcher:
            outputType = XCBOutputType.task
            pattern = .compileStoryboard

        case Matcher.copyHeaderMatcher:
            outputType = XCBOutputType.task
            pattern = .copyHeader

        case Matcher.copyPlistMatcher:
            outputType = XCBOutputType.task
            pattern = .copyPlist

        case Matcher.copyStringsMatcher:
            outputType = XCBOutputType.task
            pattern = .copyStrings

        case Matcher.cpresourceMatcher:
            outputType = XCBOutputType.task
            pattern = .cpresource

        case Matcher.executedMatcher:
            outputType = XCBOutputType.task
            pattern = .undefined

            parseSummary(line: line, colored: colored)

        case Matcher.failingTestMatcher:
            outputType = XCBOutputType.error
            pattern = .failingTest

        case Matcher.uiFailingTestMatcher:
            outputType = XCBOutputType.error
            pattern = .uiFailingTest

        case Matcher.restartingTestsMatcher:
            outputType = XCBOutputType.task
            pattern = .restartingTests

        case Matcher.generateCoverageDataMatcher:
            outputType = XCBOutputType.task
            pattern = .generateCoverageData

        case Matcher.generatedCoverageReportMatcher:
            outputType = XCBOutputType.task
            pattern = .generatedCoverageReport

        case Matcher.generateDsymMatcher:
            outputType = XCBOutputType.task
            pattern = .generateDsym

        case Matcher.libtoolMatcher:
            outputType = XCBOutputType.task
            pattern = .libtool

        case Matcher.linkingMatcher:
            outputType = XCBOutputType.task
            pattern = .linking

        case Matcher.testCasePassedMatcher:
            outputType = XCBOutputType.task
            pattern = .testCasePassed

        case Matcher.testCaseStartedMatcher:
            outputType = XCBOutputType.task
            pattern = .testCaseStarted

        case Matcher.testCasePendingMatcher:
            outputType = XCBOutputType.task
            pattern = .testCasePending

        case Matcher.testCaseMeasuredMatcher:
            outputType = XCBOutputType.task
            pattern = .testCaseMeasured

        case Matcher.phaseSuccessMatcher:
            outputType = XCBOutputType.result
            pattern = .phaseSuccess

        case Matcher.phaseScriptExecutionMatcher:
            outputType = XCBOutputType.task
            pattern = .phaseScriptExecution

        case Matcher.processPchMatcher:
            outputType = XCBOutputType.task
            pattern = .processPch

        case Matcher.processPchCommandMatcher:
            outputType = XCBOutputType.task
            pattern = .processPchCommand

        case Matcher.preprocessMatcher:
            outputType = XCBOutputType.task
            pattern = .preprocess

        case Matcher.pbxcpMatcher:
            outputType = XCBOutputType.task
            pattern = .pbxcp

        case Matcher.processInfoPlistMatcher:
            outputType = XCBOutputType.task
            pattern = .processInfoPlist

        case Matcher.testsRunCompletionMatcher:
            outputType = XCBOutputType.task
            pattern = .testsRunCompletion

        case Matcher.testSuiteStartedMatcher:
            outputType = XCBOutputType.task
            pattern = .testSuiteStarted

        case Matcher.testSuiteStartMatcher:
            outputType = XCBOutputType.task
            pattern = .testSuiteStart

        case Matcher.tiffutilMatcher:
            outputType = XCBOutputType.task
            pattern = .tiffutil

        case Matcher.touchMatcher:
            outputType = XCBOutputType.task
            pattern = .touch

        case Matcher.writeFileMatcher:
            outputType = XCBOutputType.task
            pattern = .writeFile

        case Matcher.writeAuxiliaryFilesMatcher:
            outputType = XCBOutputType.task
            pattern = .writeAuxiliaryFiles

        case Matcher.parallelTestCasePassedMatcher:
            outputType = XCBOutputType.task
            pattern = .parallelTestCasePassed

        case Matcher.parallelTestCaseAppKitPassedMatcher:
            outputType = XCBOutputType.task
            pattern = .parallelTestCaseAppKitPassed

        case Matcher.parallelTestingStartedMatcher:
            outputType = XCBOutputType.task
            pattern = .parallelTestingStarted

        case Matcher.parallelTestingPassedMatcher:
            outputType = XCBOutputType.task
            pattern = .parallelTestingPassed

        case Matcher.parallelTestSuiteStartedMatcher:
            outputType = XCBOutputType.task
            pattern = .parallelTestSuiteStarted

        case Matcher.compileWarningMatcher:
            outputType = XCBOutputType.warning
            pattern = .compileWarning

        case Matcher.ldWarningMatcher:
            outputType = XCBOutputType.warning
            pattern = .ldWarning

        case Matcher.genericWarningMatcher:
            outputType = XCBOutputType.warning
            pattern = .genericWarning

        case Matcher.willNotBeCodeSignedMatcher:
            outputType = XCBOutputType.warning
            pattern = .willNotBeCodeSigned

        case Matcher.clangErrorMatcher:
            outputType = XCBOutputType.error
            pattern = .clangError

        case Matcher.checkDependenciesErrorsMatcher:
            outputType = XCBOutputType.error
            pattern = .checkDependenciesErrors

        case Matcher.provisioningProfileRequiredMatcher:
            outputType = XCBOutputType.warning
            pattern = .provisioningProfileRequired

        case Matcher.noCertificateMatcher:
            outputType = XCBOutputType.warning
            pattern = .noCertificate

        case Matcher.compileErrorMatcher:
            outputType = XCBOutputType.error
            pattern = .compileError

        case Matcher.cursorMatcher:
            outputType = XCBOutputType.warning
            pattern = .cursor

        case Matcher.fatalErrorMatcher:
            outputType = XCBOutputType.error
            pattern = .fatalError

        case Matcher.fileMissingErrorMatcher:
            outputType = XCBOutputType.error
            pattern = .fileMissingError

        case Matcher.ldErrorMatcher:
            outputType = XCBOutputType.error
            pattern = .ldError

        case Matcher.linkerDuplicateSymbolsLocationMatcher:
            outputType = XCBOutputType.error
            pattern = .linkerDuplicateSymbolsLocation

        case Matcher.linkerDuplicateSymbolsMatcher:
            outputType = XCBOutputType.error
            pattern = .linkerDuplicateSymbols

        case Matcher.linkerUndefinedSymbolLocationMatcher:
            outputType = XCBOutputType.error
            pattern = .linkerUndefinedSymbolLocation

        case Matcher.linkerUndefinedSymbolsMatcher:
            outputType = XCBOutputType.error
            pattern = .linkerUndefinedSymbols

        case Matcher.podsErrorMatcher:
            outputType = XCBOutputType.error
            pattern = .podsError

        case Matcher.symbolReferencedFromMatcher:
            outputType = XCBOutputType.warning
            pattern = .symbolReferencedFrom

        case Matcher.moduleIncludesErrorMatcher:
            outputType = XCBOutputType.error
            pattern = .moduleIncludesError

        case Matcher.parallelTestingFailedMatcher:
            outputType = XCBOutputType.error
            pattern = .parallelTestingFailed

        case Matcher.parallelTestCaseFailedMatcher:
            outputType = XCBOutputType.error
            pattern = .parallelTestCaseFailed

        case Matcher.shellCommandMatcher:
            outputType = XCBOutputType.task
            pattern = .shellCommand

        case Matcher.undefinedSymbolLocationMatcher:
            outputType = .warning
            pattern = .undefinedSymbolLocation

        case Matcher.noSpaceOnDevice:
            outputType = .error
            pattern = .noSpaceOnDevice

        case Matcher.checkingForCrashReports:
            outputType = .error
            pattern = .checkingForCrashReports

        case Matcher.encounteredAnError:
            outputType = .error
            pattern = .encounteredAnError

        case Matcher.encounteredAnSimulatorError:
            outputType = .error
            pattern = .encounteredAnSimulatorError

        case Matcher.testingFailed:
            outputType = .result
            pattern = .testingFailed

        default:
            outputType = XCBOutputType.undefined
            pattern = .undefined
        }

        let outputText = line.beautify(pattern: pattern, colored: colored)
        let outputValues = line.values(pattern: pattern)

        return (outputText, outputType, pattern, outputValues)
    }

    func parseSummary(line: String, colored: Bool) {
        let groups = line.capturedNamedGroups(with: .executed)
        summary = TestSummary(
            testsCount: groups["numberOfTests"] ?? "0",
            failuresCount: groups["numberOfFailures"] ?? "0",
            unexpectedCount: groups["numberOfUnexpectedFailures"] ?? "0",
            time: groups["time"] ?? "-1",
            colored: colored
        )
    }
}
