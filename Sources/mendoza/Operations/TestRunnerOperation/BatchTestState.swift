import Foundation

/// Framing bytes before decoding preserves split UTF-8 characters and never parses a partial line.
struct BatchLineFramer {
    private var pending = Data()

    mutating func append(_ data: Data, flush: Bool = false) -> [String] {
        pending.append(data)
        var lines = [String]()
        while let end = pending.firstIndex(of: 10) {
            lines.append(String(decoding: pending[..<end], as: UTF8.self).trimmingCharacters(in: .newlines))
            pending.removeSubrange(...end)
        }
        if flush, !pending.isEmpty {
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        return lines
    }
}

enum BatchLineEvent: Equatable {
    case started(TestCase)
    case finished(TestCase, passed: Bool)
    case skipped(TestCase)
    case interrupted(TestCase?)
    case noSpace
}

struct BatchOutputParser {
    let target: String

    func event(_ line: String) -> BatchLineEvent? {
        let module = NSRegularExpression.escapedPattern(for: target.replacingOccurrences(of: " ", with: "_"))
        let identity = #"Test Case '-\["# + module + #"\.([^ ]+) ([^\]]+)\]' "#
        if let groups = try? line.capturedGroups(withRegexString: identity + #"(started|passed|failed|skipped|exceeded execution time allowance)"#), groups.count == 3 {
            let test = TestCase(name: groups[1], suite: groups[0])
            switch groups[2] {
            case "started": return .started(test)
            case "passed": return .finished(test, passed: true)
            case "skipped": return .skipped(test)
            case "failed": return .finished(test, passed: false)
            default: return .interrupted(test)
            }
        }
        // Named crash messages can arrive after the active test's terminal line. Never apply those to its sibling.
        for pattern in [#"Restarting after unexpected exit or crash in ([^/ ]+)/([^ (]+)\(\)"#,
                        #"Restarting after unexpected exit, crash, or test timeout in (\S+)\.([^ .(]+)\(\)"#] {
            if let groups = try? line.capturedGroups(withRegexString: pattern), groups.count == 2 {
                let suite = groups[0].hasPrefix(target + ".") ? String(groups[0].dropFirst(target.count + 1)) : groups[0]
                return .interrupted(TestCase(name: groups[1], suite: suite))
            }
        }
        if line.contains("No space left on device") {
            return .noSpace
        }
        if line.contains("Checking for crash reports corresponding to unexpected termination of") ||
            line.contains("encountered an error (Crash:") || line.contains("encountered an error (Test runner exited") {
            return .interrupted(nil)
        }
        return nil
    }
}

/// One invocation, many test verdicts. All mutations happen on the worker's single read loop.
struct BatchTestState {
    let tests: [TestCase]
    let node: String
    let runnerName: String
    let runnerIdentifier: String
    let launchedAt: TimeInterval
    private(set) var results = [TestCaseResult]()
    private(set) var active: TestCase?
    private(set) var started = Set<TestCase>()
    private(set) var abortReason: String?
    private(set) var phaseStart: TimeInterval
    private var activeStart: TimeInterval = 0
    private var lastOutput: TimeInterval = 0
    private var idleTimes = [TimeInterval]()

    init(tests: [TestCase], node: String, runnerName: String, runnerIdentifier: String, now: TimeInterval) {
        self.tests = tests
        self.node = node
        self.runnerName = runnerName
        self.runnerIdentifier = runnerIdentifier
        self.launchedAt = now
        self.phaseStart = now
    }

    var remaining: [TestCase] {
        tests.filter { test in !results.contains { $0.testCaseIdentifier == test.testIdentifier } }
    }

    mutating func output(at now: TimeInterval) {
        guard active != nil, abortReason == nil else { return }
        idleTimes.append(max(0, now - lastOutput))
        lastOutput = now
    }

    mutating func consume(_ event: BatchLineEvent, at now: TimeInterval) {
        guard abortReason == nil else { return }
        switch event {
        case let .started(test):
            guard tests.contains(test), !started.contains(test), remaining.contains(test) else {
                abort("Unexpected or repeated test start: \(test.testIdentifier)", at: now)
                return
            }
            // Xcode can restart the runner after a crash without printing the interrupted method's verdict.
            if let active {
                finish(active, passed: false, at: now)
            }
            active = test
            started.insert(test)
            activeStart = now
            lastOutput = now
            idleTimes = []
        case let .finished(test, passed):
            // Repeated terminal messages are harmless, but mismatched identities must never pass another test.
            if results.contains(where: { $0.testCaseIdentifier == test.testIdentifier }) {
                return
            }
            guard active == test else {
                abort("Test verdict without matching start: \(test.testIdentifier)", at: now)
                return
            }
            finish(test, passed: passed, at: now)
        case let .skipped(test):
            if results.contains(where: { $0.testCaseIdentifier == test.testIdentifier }) {
                return
            }
            guard tests.contains(test), active == nil || active == test else {
                abort("Unexpected skipped test: \(test.testIdentifier)", at: now)
                return
            }
            finish(test, passed: true, at: now)
        case let .interrupted(test):
            if let test, results.contains(where: { $0.testCaseIdentifier == test.testIdentifier }) {
                return
            }
            abort("Test process crashed or exceeded its execution allowance", at: now)
        case .noSpace:
            abort("No space left on device", at: now)
        }
    }

    mutating func checkTimeout(now: TimeInterval, idleLimit: TimeInterval?, executionLimit: TimeInterval?, startupLimit: TimeInterval = 180, transitionLimit: TimeInterval = 120, finalizationLimit: TimeInterval = 900) {
        guard abortReason == nil else { return }
        if active != nil {
            if let idleLimit, now - lastOutput > idleLimit {
                abort("Active test stdout timeout", at: now)
            }
            if let executionLimit, now - activeStart > executionLimit {
                abort("Active test execution timeout", at: now)
            }
        } else {
            let limit = remaining.isEmpty ? finalizationLimit : (started.isEmpty ? startupLimit : transitionLimit)
            if now - phaseStart > limit {
                abort("Invocation phase timeout", at: now)
            }
        }
    }

    mutating func abort(_ reason: String, at now: TimeInterval) {
        guard abortReason == nil else { return }
        abortReason = reason
        if let active {
            finish(active, passed: false, at: now)
        }
    }

    mutating func complete(at now: TimeInterval) {
        if let active {
            finish(active, passed: false, at: now)
        }
        // A launch failure must consume an attempt to ensure bounded retries. Untouched siblings are deferred.
        if results.isEmpty, let first = remaining.first {
            finish(first, passed: false, at: now)
            return
        }
        // Any untouched sibling is returned once as a singleton. A singleton launch failure above consumes an attempt.
    }

    private mutating func finish(_ test: TestCase, passed: Bool, at now: TimeInterval) {
        let start = active == test ? activeStart : now
        results.append(TestCaseResult(node: node, runnerName: runnerName, runnerIdentifier: runnerIdentifier, xcResultPath: "", suite: test.suite, name: test.name, status: passed ? .passed : .failed, startInterval: start, endInterval: now, averageStdOutIdleTime: idleTimes.isEmpty ? nil : idleTimes.reduce(0, +) / Double(idleTimes.count), maxStdOutIdleTime: idleTimes.max()))
        active = nil
        idleTimes = []
        phaseStart = now
    }
}
