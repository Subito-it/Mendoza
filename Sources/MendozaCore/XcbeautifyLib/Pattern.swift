public enum Pattern: String {
    /// Regular expression captured groups:
    /// $1 = filePath
    /// $2 = filename
    /// $3 = target
    /// $4 = project
    case analyze = #"Analyze(?:Shallow)?\s(?<filePath>.*\/(?<fileName>.*\.(?:m|mm|cc|cpp|c|cxx)))\s.*\((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = target
    /// $2 = project
    /// $3 = configuration
    case buildTarget = #"=== BUILD TARGET\s(?<target>.*)\sOF PROJECT\s(?<project>.*)\sWITH.*CONFIGURATION\s(?<configuration>.*)\s==="#

    /// Regular expression captured groups:
    /// $1 = target
    /// $2 = project
    /// $3 = configuration
    case aggregateTarget = #"=== BUILD AGGREGATE TARGET\s(?<target>.*)\sOF PROJECT\s(?<project>.*)\sWITH.*CONFIGURATION\s(?<configuration>.*)\s==="#

    /// Regular expression captured groups:
    /// $1 = target
    /// $2 = project
    /// $3 = configuration
    case analyzeTarget = #"=== ANALYZE TARGET\s(?<target>.*)\sOF PROJECT\s(?<project>.*)\sWITH.*CONFIGURATION\s(?<configuration>.*)\s==="#

    /// Nothing returned here for now
    case checkDependencies = #"Check dependencies"#

    /// Regular expression captured groups:
    /// $1 = command path
    /// $2 = arguments
    case shellCommand = #"\s{4}(?<key>cd|setenv|(?:[\w\/:\s\-.]+?\/)?[\w\-]+)\s(?<value>.*)$"#

    /// Nothing returned here for now
    case cleanRemove = #"Clean.Remove(?<clean>.*)"#

    /// Regular expression captured groups:
    /// $1 = target
    /// $2 = project
    /// $3 = configuration
    case cleanTarget = #"=== CLEAN TARGET\s(?<target>.*)\sOF PROJECT\s(?<project>.*)\sWITH CONFIGURATION\s(?<configuration>.*)\s==="#

    /// Regular expression captured groups:
    /// $1 = file
    case codesign = #"CodeSign\s(?<file>(?:\ |[^ ])*)$"#

    /// Regular expression captured groups:
    /// $1 = file
    case codesignFramework = #"CodeSign\s(?<file>(?:\ |[^ ])*.framework)\/Versions/A"#

    #if os(Linux)
    /// Regular expression captured groups:
    /// $1 = filename (e.g. KWNull.m)
    /// $2 = target
        case compile = #"\[\d+\/\d+\]\sCompiling\s(?<filename>[^ ]+)\s(?<target>[^ \.]+\.(?:m|mm|c|cc|cpp|cxx|swift))"#
    #else
    /// Regular expression captured groups:
    /// $1 = file path
    /// $2 = filename (e.g. KWNull.m)
    /// $3 = target
    /// $4 = project
        case compile = #"Compile[\w]+\s.+?\s(?<filePath>(?:\.|[^ ])+\/(?<fileName>(?:\.|[^ ])+\.(?:m|mm|c|cc|cpp|cxx|swift)))\s.*\((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#
    #endif

    /// Regular expression captured groups:
    /// $1 = compiler command
    /// $2 = file path
    case compileCommand = #"\s*(?<compilerCommand>.*clang\s.*\s\-c\s(?<filePath>.*\.(?:m|mm|c|cc|cpp|cxx))\s.*\.o)$"#

    /// Regular expression captured groups:
    /// $1 = file path
    /// $2 = filename (e.g. MainMenu.xib)
    /// $3 = target
    /// $4 = project
    case compileXib = #"CompileXIB\s(?<filePath>.*\/(?<fileName>.*\.xib))\s.*\((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = file path
    /// $2 = filename (e.g. Main.storyboard)
    /// $3 = target
    /// $4 = project
    case compileStoryboard = #"CompileStoryboard\s(?<filePath>.*\/(?<fileName>[^\/].*\.storyboard))\s.*\((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = source file
    /// $2 = target file
    /// $3 = target
    /// $4 = project
    case copyHeader = #"CpHeader\s(?<sourceFile>.*\.h)\s(?<targetFile>.*\.h) \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = source file
    /// $2 = target file
    /// $3 = project
    case copyPlist = #"CopyPlistFile\s(?<sourceFile>.*\.plist)\s(.*\.plist) \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = file
    /// $2 = target file
    /// $3 = project
    case copyStrings = #"CopyStringsFile\s(?<file>.*\.strings)\s(.*\.strings) \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = resource
    /// $2 = location
    /// $3 = target file
    /// $4 = project
    case cpresource = #"CpResource\s(?<resource>.*)\s\/(?<location>.*) \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = number of tests
    /// $2 = number of failures
    /// $3 = number of unexpected failures
    /// $4 = wall clock time in seconds (e.g. 0.295)
    case executed = #"\s*Executed\s(?<numberOfTests>\d+)\stest[s]?,\swith\s(?<numberOfFailures>\d+)\sfailure[s]?\s\((?<numberOfUnexpectedFailures>\d+)\sunexpected\)\sin\s\d+\.\d{3}\s\((?<time>\d+\.\d{3})\)\sseconds"#

    /// Regular expression captured groups:
    /// $1 = file
    /// $2 = test suite
    /// $3 = test case
    /// $4 = reason
    #if os(Linux)
        case failingTest = #"\s*(?<file>.+:\d+):\serror:\s(?<testSuite>.*)\.(?<testCase>.*)\s:(?:\s'.*'\s\[failed\],)?\s(.*)"#
    #else
        case failingTest = #"\s*(?<file>.+:\d+):\serror:\s[\+\-]\[(?<testSuite>.*)\s(?<testCase>.*)\]\s:(?:\s'.*'\s\[FAILED\],)?\s(?<reason>.*)"#
    #endif

    /// Regular expression captured groups:
    /// $1 = file
    /// $2 = reason
    case uiFailingTest = #"\s{4}t = \s+\d+\.\d+s\s+Assertion Failure: (?<file>.*:\d+): (?<reason>.*)$"#

    /// Regular expression captured groups:
    case restartingTests = #"Restarting after unexpected exit or crash in.+$"#

    /// Nothing returned here for now.
    case generateCoverageData = #"generating\s+coverage\s+data\.*"#

    /// Regular expression captured groups:
    /// $1 = coverage report file path
    case generatedCoverageReport = #"generated\s+coverage\s+report:\s+(?<filePath>.+)"#

    /// Regular expression captured groups:
    /// $1 = dsym
    /// $2 = target
    /// $3 = project
    case generateDsym = #"GenerateDSYMFile \/.*\/(?<dsym>.*\.dSYM) \/.* \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = library
    /// $2 = target
    /// $3 = project
    case libtool = #"Libtool.*\/(?<library>.*) .* .* \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    #if os(Linux)
    /// Regular expression captured groups:
    /// $1 = target
        case linking = #"\[\d+\/\d+\]\sLinking\s(?<target>[^ ]+)"#
    #else
    /// Regular expression captured groups:
    /// $1 =  filename
    /// $2 = target
    /// $3 = project
        case linking = #"Ld \/?.*\/(?<fileName>.*?) normal .* \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#
    #endif

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = test case
    /// $3 = time
    #if os(Linux)
        case testCasePassed = #"\s*Test Case\s'(?<testSuite>.*)\.(?<testCase>.*)'\spassed\s\((?<time>\d*\.\d{1,3})\sseconds\)"#
    #else
        case testCasePassed = #"\s*Test Case\s'-\[(?<testSuite>.*)\s(?<testCase>.*)\]'\spassed\s\((?<time>\d*\.\d{3})\sseconds\)."#
    #endif

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = test case
    #if os(Linux)
        case testCaseStarted = #"Test Case '(?<testSuite>.*)\.(?<testCase>.*)' started at"#
    #else
        case testCaseStarted = #"Test Case '-\[(?<testSuite>.*) (?<testCase>.*)\]' started.$"#
    #endif

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = test case
    case testCasePending = #"Test Case\s'-\[(?<testSuite>.*)\s(?<testCase>.*)PENDING\]'\spassed"#

    /// $1 = suite
    /// $2 = test case
    /// $3 = time
    #if os(Linux)
        case testCaseMeasured = #"[^:]*:[^:]*:\sTest Case\s'(?<testSuite>.*)\.(?<testCase>.*)'\smeasured\s\[Time,\sseconds\]\saverage:\s(?<time>\d*\.\d{3})(.*){4}"#
    #else
        case testCaseMeasured = #"[^:]*:[^:]*:\sTest Case\s'-\[(?<testSuite>.*)\s(?<testCase>.*)\]'\smeasured\s\[Time,\sseconds\]\saverage:\s(?<time>\d*\.\d{3})(.*){4}"#
    #endif

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = test case
    /// $3 = installed app file and ID (e.g. "MyApp.app (12345)"), process (e.g. "xctest (12345)"), or device (e.g. "iPhone X")
    /// $4 = time
    case parallelTestCasePassed = #"Test\s+case\s+'(?<testSuite>.*)\.(?<testCase>.*)\(\)'\s+passed\s+on\s+'(?<description>.*)'\s+\((?<time>\d*\.(.*){3})\s+seconds\)"#

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = test case
    /// $3 = time
    case parallelTestCaseAppKitPassed = #"\s*Test case\s'-\[(?<testSuite>.*)\s(?<testCase>.*)\]'\spassed\son\s'.*'\s\((?<time>\d*\.\d{3})\sseconds\)"#

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = test case
    /// $3 = installed app file and ID (e.g. "MyApp.app (12345)"), process (e.g. "xctest (12345)"), or device (e.g. "iPhone X")
    /// $4 = time
    case parallelTestCaseFailed = #"Test\s+case\s+'(?<testSuite>.*)\.(?<testCase>.*)\(\)'\s+failed\s+on\s+'(?<description>.*)'\s+\((?<time>\d*\.(.*){3})\s+seconds\)"#

    /// Regular expression captured groups:
    /// $1 = device
    case parallelTestingStarted = #"Testing\s+started\s+on\s+'(?<device>.*)'"#

    /// Regular expression captured groups:
    /// $1 = device
    case parallelTestingPassed = #"Testing\s+passed\s+on\s+'(?<device>.*)'"#

    /// Regular expression captured groups:
    /// $1 = device
    case parallelTestingFailed = #"Testing\s+failed\s+on\s+'(?<device>.*)'"#

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = device
    case parallelTestSuiteStarted = #"\s*Test\s+Suite\s+'(?<testSuite>.*)'\s+started\s+on\s+'(?<device>.*)'"#

    /// Nothing returned here for now
    case phaseSuccess = #"\*\*\s(?<description>.*)\sSUCCEEDED\s\*\*"#

    /// Regular expression captured groups:
    /// $1 = phase name
    /// $2 = target
    /// $3 = project
    case phaseScriptExecution = #"PhaseScriptExecution\s(?<name>.*)\s\/.*\.sh\s\((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = file
    /// $2 = target
    /// $3 = project
    case processPch = #"ProcessPCH(?:\+\+)?\s.*\s\/.*\/(?<file>.*.pch) normal .* .* .* \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 file path
    case processPchCommand = #"\s*.*\/usr\/bin\/clang\s.*\s\-c\s(?<filePath>.*.pch)\s.*\-o\s.*"#

    /// Regular expression captured groups:
    /// $1 = file
    case preprocess = #"Preprocess\s(?:(?:\ |[^ ])*)\s(?<file>(?:\ |[^ ])*)$"#

    /// Regular expression captured groups:
    /// $1 = source file
    /// $2 = target file
    /// $3 = target
    /// $4 = project
    case pbxcp = #"PBXCp\s(?<file>.*)\s\/(?<targetFile>.*)\s\((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\)"#

    /// Regular expression captured groups:
    /// $1 = file path
    /// $2 = filename
    /// $4 = target
    /// $5 = project
    case processInfoPlist = #"ProcessInfoPlistFile\s.*\.plist\s(?<filePath>.*\/+(?<fileName>.*\.plist))( \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\))?"#

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = result
    /// $3 = time
    #if os(Linux)
        case testsRunCompletion = #"\s*Test Suite '(?<testSuite>.*)' (?<result>finished|passed|failed) at (?<time>.*)"#
    #else
        case testsRunCompletion = #"\s*Test Suite '(?:.*\/)?(?<testSuite>.*[ox]ctest.*)' (?<result>finished|passed|failed) at (?<time>.*)"#
    #endif

    /// Regular expression captured groups:
    /// $1 = suite
    /// $2 = time
    #if os(Linux)
        case testSuiteStarted = #"\s*Test Suite '(?<testSuite>.*)' started at(?<time>.*)"#
    #else
        case testSuiteStarted = #"\s*Test Suite '(?:.*\/)?(?<testSuite>.*[ox]ctest.*)' started at(?<time>.*)"#
    #endif

    /// Regular expression captured groups:
    /// $1 = test suite name
    case testSuiteStart = #"\s*Test Suite '(?<testSuite>.*)' started at"#

    /// Regular expression captured groups:
    /// $1 = filename
    case tiffutil = #"TiffUtil\s(?<fileName>.*)"#

    /// Regular expression captured groups:
    /// $1 = filePath
    /// $2 = filename
    /// $3 = target
    /// $4 = project
    case touch = #"Touch\s(?<filePath>.*\/(?<fileName>.+))( \((in target:? '?(?<target>.*[^'])'? from project '(?<project>.*)')\))"#

    /// Regular expression captured groups:
    /// $1 = file path
    case writeFile = #"write-file\s(?<filePath>.*)"#

    /// Nothing returned here for now
    case writeAuxiliaryFiles = #"Write auxiliary files"#

    // MARK: - Warning

    /// Regular expression captured groups:
    /// $1 = file path
    /// $2 = filename
    /// $3 = reason
    case compileWarning = #"(?<filePath>(?<fileName>.*):.*:.*):\swarning:\s(?<reason>.*)$"#

    /// Regular expression captured groups:
    /// $1 = ld prefix
    /// $2 = warning message
    case ldWarning = #"(?<prefix>ld: )warning: (?<message>.*)"#

    /// Regular expression captured groups:
    /// $1 = whole warning
    case genericWarning = #"warning:\s(?<message>.*)$"#

    /// Regular expression captured groups:
    /// $1 = whole warning
    case willNotBeCodeSigned = #"(?<message>.* will not be code signed because .*)$"#

    // MARK: - Error

    /// Regular expression captured groups:
    /// $1 = whole error
    case clangError = #"(?<message>clang: error:.*)$"#

    /// Regular expression captured groups:
    /// $1 = whole error
    case checkDependenciesErrors = #"(?<message>Code\s?Sign error:.*|Code signing is required for product type .* in SDK .*|No profile matching .* found:.*|Provisioning profile .* doesn't .*|Swift is unavailable on .*|.?Use Legacy Swift Language Version.*)$"#

    /// Regular expression captured groups:
    /// $1 = whole error
    case provisioningProfileRequired = #"(?<message>.*requires a provisioning profile.*)$"#

    /// Regular expression captured groups:
    /// $1 = whole error
    case noCertificate = #"(?<message>No certificate matching.*)$"#

    /// Regular expression captured groups:
    /// $1 = file path (could be a relative path if you build with Bazel)
    /// $2 = is fatal error
    /// $3 = reason
    case compileError = #"(?<filePath>(.*):.*:.*):\s(?:fatal\s)?error:\s(?<reason>.*)$"#

    /// Regular expression captured groups:
    /// $1 = cursor (with whitespaces and tildes)
    case cursor = #"(?<cursor>[\s~]*\^[\s~]*)$"#

    /// Regular expression captured groups:
    /// $1 = whole error.
    /// it varies a lot, not sure if it makes sense to catch everything separately
    case fatalError = #"(?<message>fatal error:.*)$"#

    /// Regular expression captured groups:
    /// $1 = whole error.
    /// $2 = file path
    case fileMissingError = #"<unknown>:0:\s(?<message>error:\s.*)\s'(?<filePath>\/.+\/.*\..*)'$"#

    /// Regular expression captured groups:
    /// $1 = whole error
    case ldError = #"(?<message>ld:.*)"#

    /// Regular expression captured groups:
    /// $1 = file path
    case linkerDuplicateSymbolsLocation = #"\s+(?<filePath>\/.*\.o[\)]?)$"#

    /// Regular expression captured groups:
    /// $1 = reason
    case linkerDuplicateSymbols = #"(?<message>duplicate symbol .*):$"#

    /// Regular expression captured groups:
    /// $1 = symbol location
    case linkerUndefinedSymbolLocation = #"(?<location>.* in .*\.o)$"#

    /// Regular expression captured groups:
    /// $1 = reason
    case linkerUndefinedSymbols = #"(?<message>Undefined symbols for architecture .*):$"#

    /// Regular expression captured groups:
    /// $1 = reason
    case podsError = #"(?<message>error:\s.*)"#

    /// Regular expression captured groups:
    /// $1 = reference
    case symbolReferencedFrom = #"\s+\"(?<reference>.*)\", referenced from:$"#

    /// Regular expression captured groups:
    /// $1 = error reason
    case moduleIncludesError = #"\<module-includes\>:.*?:.*?:\s(?:fatal\s)?(?<message>error:\s.*)$/"#

    /// Regular expression captured groups:
    /// $1 = target
    /// $2 = filename
    case undefinedSymbolLocation = #".+ in (?<target>.+)\((?<fileName>.+)\.o\)$"#

    /// Regular expression captured groups:
    case noSpaceOnDevice = ##"Code=28 "No space left on device""##

    case checkingForCrashReports = #"Checking for crash reports corresponding to unexpected termination of"#

    case encounteredAnError = #"\s+(?<message>.*)\(\) encountered an error \(Crash:"#

    case encounteredAnSimulatorError = #"\s+(?<message>.*)\(\) encountered an error \(Test runner exited"# // Should be caused by the force reset of simulator

    case testingFailed = #"^(Testing failed:)$"#
}
