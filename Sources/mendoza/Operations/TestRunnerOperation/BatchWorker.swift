import Darwin
import Foundation

struct BatchRequest: Codable {
    static let protocolVersion = 1
    let version: Int
    let identifier: String
    let tests: [TestCase]
    let target: String
    let node: String
    let runnerName: String
    let runnerIdentifier: String
    let xctestrun: String
    let directory: String
    let resultPath: String
    let idleTimeout: Int?
    let executionTimeout: Int?
    let collectDiagnostics: Bool
    let appBundleIdentifier: String
    let testBundleIdentifier: String

    var arguments: [String] {
        var args = ["xcodebuild", "-parallel-testing-enabled", "NO", "-disable-concurrent-destination-testing",
                    "-xctestrun", xctestrun, "-destination", "platform=iOS Simulator,id=\(runnerIdentifier)",
                    "-derivedDataPath", directory + "/derived", "-resultBundlePath", resultPath,
                    "-enableCodeCoverage", "YES", "-destination-timeout", "60", "-test-timeouts-enabled", "YES",
                    "-collect-test-diagnostics", collectDiagnostics ? "on-failure" : "never"]
        if let executionTimeout {
            args += ["-maximum-test-execution-time-allowance", String(executionTimeout)]
        }
        args += tests.map { "-only-testing:\(target)/\($0.testIdentifier)" }
        return args + ["test-without-building"]
    }
}

struct BatchCompletion: Codable {
    let identifier: String
    let results: [TestCaseResult]
    let unstarted: [TestCase]
    let started: [TestCase]
    let exitStatus: Int32
    let interruption: String?
}

/// Runs on the node owning the simulator. It alone owns the child process group and its timers.
/// No SSH calls or shared Executer state participate in watchdog handling.
enum BatchWorker {
    static let previewPrefix = "MENDOZA_BATCH_RESULT:"

    static func run(requestPath: String) throws {
        let request = try JSONDecoder().decode(BatchRequest.self, from: Data(contentsOf: URL(fileURLWithPath: requestPath)))
        guard request.version == BatchRequest.protocolVersion, (1 ... 2).contains(request.tests.count),
              Set(request.tests).count == request.tests.count else { throw Error("Invalid batch request") }
        try validateTestRun(request.xctestrun)
        // SSH hangup or a terminated controller must enter the same cleanup path as a watchdog.
        // Swift cleanup cannot run from a POSIX signal handler; dispatch sources write the cancellation marker.
        let signalQueue = DispatchQueue(label: "mendoza.batch.signals")
        let signals = [SIGHUP, SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: signalQueue)
            source.setEventHandler {
                try? Data().write(to: URL(fileURLWithPath: request.directory + "/cancel"), options: .atomic)
            }
            source.resume()
            return source
        }
        defer { signals.forEach { $0.cancel() } }
        let completion = try execute(request)
        try JSONEncoder().encode(completion).write(to: URL(fileURLWithPath: request.directory + "/completion.json"), options: .atomic)
    }

    /// Batch execution owns retries; plans that repeat a method would violate its one-attempt accounting.
    static func validateTestRun(_ path: String) throws {
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil)
        func validate(_ value: Any) throws {
            if let dict = value as? [String: Any] {
                for (key, value) in dict {
                    if ["RetryTestsOnFailure", "RunTestsUntilFailure"].contains(key), (value as? Bool) == true {
                        throw Error("Batching does not support xctestrun repetition: \(key)")
                    }
                    if ["TestRepetitionMode", "repetitionMode"].contains(key), let mode = value as? String,
                       !["none", "disabled"].contains(mode.lowercased()) {
                        throw Error("Batching does not support xctestrun repetition: \(mode)")
                    }
                    if ["TestIterations", "MaximumTestRepetitions"].contains(key), let count = value as? Int, count > 1 {
                        throw Error("Batching does not support repeated tests")
                    }
                    try validate(value)
                }
            } else if let values = value as? [Any] {
                for value in values {
                    try validate(value)
                }
            }
        }
        try validate(plist)
    }

    /// Internal executable override permits deterministic watchdog/process tests without simulators.
    static func execute(_ request: BatchRequest, executable: String = "/usr/bin/xcrun", arguments: [String]? = nil,
                        emit: (TestCaseResult) -> Void = emitPreview) throws -> BatchCompletion {
        let fm = FileManager.default
        try fm.createDirectory(atPath: request.directory, withIntermediateDirectories: true)
        let logPath = request.directory + "/xcodebuild.log"
        fm.createFile(atPath: logPath, contents: nil)
        let log = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        defer { try? log.close() }

        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw Error("Cannot create batch stdout pipe") }
        defer { close(fds[0]) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // The worker ignores termination signals to perform cleanup; the child needs normal dispositions.
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for number in [SIGHUP, SIGINT, SIGTERM, SIGPIPE] {
            sigaddset(&defaultSignals, number)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attributes, 0)
        let strings = ([executable] + (arguments ?? request.arguments)).map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var argv = strings + [nil]
        let environmentStrings = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        defer { environmentStrings.forEach { free($0) } }
        var environment = environmentStrings + [nil]
        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, executable, &actions, &attributes, &argv, &environment)
        close(fds[1])
        guard spawnStatus == 0 else { throw Error("Cannot launch batch process: \(spawnStatus)") }
        // Keep the child unreaped until its entire process group has been cleaned up. This prevents PID reuse.
        defer {
            kill(-pid, SIGKILL)
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        }
        _ = fcntl(fds[0], F_SETFL, O_NONBLOCK)

        var state = BatchTestState(tests: request.tests, node: request.node, runnerName: request.runnerName, runnerIdentifier: request.runnerIdentifier, now: CFAbsoluteTimeGetCurrent())
        let parser = BatchOutputParser(target: request.target)
        var framer = BatchLineFramer()
        var emittedCount = 0
        var interruptTime: TimeInterval?
        var didTerminateGroup = false
        var status: Int32 = 0
        var reachedEOF = false
        var childExited = false
        var childExitTime: TimeInterval?
        var terminators = [Process]()
        let terminationBundles = terminationBundleIdentifiers(request)
        let parent = getppid()
        defer {
            for process in terminators {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
            }
        }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            var descriptor = pollfd(fd: fds[0], events: Int16(POLLIN | POLLHUP), revents: 0)
            _ = poll(&descriptor, 1, 100)
            let count = read(fds[0], &buffer, buffer.count)
            let now = CFAbsoluteTimeGetCurrent()
            if count > 0 {
                let data = Data(buffer.prefix(count))
                try log.write(contentsOf: data)
                state.output(at: now)
                for line in framer.append(data) {
                    if let event = parser.event(line) {
                        state.consume(event, at: now)
                    }
                }
            } else if count == 0 {
                reachedEOF = true
            }

            if fm.fileExists(atPath: request.directory + "/cancel") {
                state.abort("Batch cancelled", at: now)
            }
            if getppid() != parent {
                state.abort("Batch controller disconnected", at: now)
            }
            state.checkTimeout(now: now, idleLimit: request.idleTimeout.map(Double.init), executionLimit: request.executionTimeout.map(Double.init))
            if state.abortReason != nil, interruptTime == nil {
                interruptTime = now
                // Cancel xcodebuild immediately so it cannot schedule an untouched sibling while we flush artifacts.
                kill(-pid, SIGINT)
                // Terminate only applications on this simulator first, allowing xcodebuild to flush coverage/results.
                if executable == "/usr/bin/xcrun" {
                    for bundle in terminationBundles {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                        process.arguments = ["simctl", "terminate", request.runnerIdentifier, bundle]
                        process.standardOutput = FileHandle.nullDevice
                        process.standardError = FileHandle.nullDevice
                        if (try? process.run()) != nil {
                            terminators.append(process)
                        }
                        // Never block the worker on a wedged simctl.
                    }
                }
            }
            if let interruptTime, now - interruptTime > 10, !didTerminateGroup {
                kill(-pid, SIGTERM)
                didTerminateGroup = true
            }
            if let interruptTime, now - interruptTime > 15 {
                kill(-pid, SIGKILL)
            }

            for result in state.results.dropFirst(emittedCount) {
                emit(result)
            }
            emittedCount = state.results.count

            // waitid(WNOWAIT) observes completion while retaining ownership of the process-group id.
            var info = siginfo_t()
            if waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0, info.si_pid == pid {
                status = info.si_status
                childExited = true
                if childExitTime == nil {
                    childExitTime = now
                }
            }
            if childExited, reachedEOF {
                break
            }
            if let childExitTime, now - childExitTime > 1, count < 0, interruptTime == nil, !reachedEOF {
                // A descendant holding stdout open must not hang finalization forever.
                state.abort("Child exited with stdout still open", at: now)
            }
            if let interruptTime, now - interruptTime > 20 {
                break
            }
        }
        for line in framer.append(Data(), flush: true) {
            if let event = parser.event(line) {
                state.consume(event, at: CFAbsoluteTimeGetCurrent())
            }
        }
        state.complete(at: CFAbsoluteTimeGetCurrent())
        for result in state.results.dropFirst(emittedCount) {
            emit(result)
        }
        return BatchCompletion(identifier: request.identifier, results: state.results, unstarted: state.remaining, started: Array(state.started), exitStatus: status, interruption: state.abortReason)
    }

    private static func emitPreview(_ result: TestCaseResult) {
        if let data = try? JSONEncoder().encode(result) {
            print(previewPrefix + String(decoding: data, as: UTF8.self))
            fflush(stdout)
        }
    }

    private static func terminationBundleIdentifiers(_ request: BatchRequest) -> [String] {
        var identifiers = [request.appBundleIdentifier]
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if dictionary["BlueprintName"] as? String == request.target,
                   let host = dictionary["TestHostBundleIdentifier"] as? String {
                    identifiers.append(host)
                }
                dictionary.values.forEach(visit)
            } else if let values = value as? [Any] {
                values.forEach(visit)
            }
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: request.xctestrun)),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            visit(plist)
        }
        if identifiers.count == 1 {
            identifiers.append(request.testBundleIdentifier)
        }
        return Array(Set(identifiers))
    }
}
