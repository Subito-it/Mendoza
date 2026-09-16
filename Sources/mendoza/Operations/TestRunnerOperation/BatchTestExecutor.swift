import Foundation

/// Batch-only execution path. The legacy TestCaseExecutor remains the size-1 implementation.
final class BatchTestExecutor {
    struct Outcome {
        let results: [TestCaseResult]
        let unstarted: [TestCase]
        let requiresQuarantine: Bool
    }

    private let configuration: Configuration
    private let target: String
    private let baseUrl: URL
    private let destinationPath: String
    private let jobs: ThreadQueue
    private let addLogger: (ExecuterLogger) -> Void
    private let sync = DispatchQueue(label: "mendoza.batch.jobs")
    private var controls = [String: Executer]()
    private var cancelled = false
    private var jobErrors = [String]()
    private var checkpoints = [String: String]()

    init(configuration: Configuration, target: String, baseUrl: URL, destinationPath: String, jobs: ThreadQueue, addLogger: @escaping (ExecuterLogger) -> Void) {
        self.configuration = configuration
        self.target = target
        self.baseUrl = baseUrl
        self.destinationPath = destinationPath
        self.jobs = jobs
        self.addLogger = addLogger
    }

    static func quote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func cancel() {
        let active = sync.sync { () -> [String: Executer] in
            guard !cancelled else { return [:] }
            cancelled = true
            return controls
        }
        for (directory, executer) in active {
            do { _ = try executer.execute("touch " + Self.quote(directory + "/cancel")) }
            catch { executer.logger?.log(exception: "Failed to signal batch cancellation: \(error)") }
        }
    }

    func finish() throws {
        jobs.waitUntilAllOperationsAreFinished()
        let errors = sync.sync { jobErrors }
        guard errors.isEmpty else { throw Error("Batch artifact processing failed:\n" + errors.joined(separator: "\n")) }
    }

    func execute(tests: [TestCase], executer: Executer, node: Node, runner: TestRunner,
                 preview: @escaping (TestCaseResult, TestCase) -> Void) throws -> Outcome {
        let q = Self.quote
        guard let executablePath = Bundle.main.executableURL?.path else { throw Error("Cannot locate the Mendoza batch worker executable") }
        let worker = executer is LocalExecuter ? executablePath : "mendoza"
        let capability = try executer.execute(q(worker) + " mendoza batch_protocol").trimmingCharacters(in: .whitespacesAndNewlines)
        guard capability == String(BatchRequest.protocolVersion) else {
            throw Error("Node \(node.address) needs a Mendoza binary supporting batch protocol \(BatchRequest.protocolVersion)")
        }
        let testRuns = try executer.execute("find \(q(Path.testBundle.rawValue)) -type f -name \(q(configuration.building.scheme + "*.xctestrun"))")
            .components(separatedBy: "\n").filter { !$0.isEmpty }
        guard testRuns.count == 1 else { throw Error("Expected exactly one xctestrun for batch execution") }
        let identifier = UUID().uuidString
        let directory = Path.temp.rawValue + "/batches/" + identifier
        let resultPath = Path.results.rawValue + "/" + runner.id + "/" + identifier + ".xcresult"
        _ = try executer.execute("mkdir -p \(q(directory)) \(q(URL(fileURLWithPath: resultPath).deletingLastPathComponent().path))")
        let request = BatchRequest(version: BatchRequest.protocolVersion, identifier: identifier, tests: tests, target: target, node: node.address, runnerName: runner.name, runnerIdentifier: runner.id, xctestrun: testRuns[0], directory: directory, resultPath: resultPath, idleTimeout: configuration.testing.maximumStdOutIdleTime, executionTimeout: configuration.testing.maximumTestExecutionTime, collectDiagnostics: configuration.testing.collectTestDiagnosticsOnFailure, appBundleIdentifier: configuration.building.buildBundleIdentifier, testBundleIdentifier: configuration.building.testBundleIdentifier)
        try upload(JSONEncoder().encode(request), to: directory + "/request.json", executer: executer)
        let control = try executer.clone()
        let shouldCancel = sync.sync { () -> Bool in
            controls[directory] = control
            return cancelled
        }
        defer { _ = sync.sync { controls.removeValue(forKey: directory) } }
        if shouldCancel {
            _ = try control.execute("touch " + q(directory + "/cancel"))
        }

        var framer = BatchLineFramer()
        var emitted = Set<String>()
        let progressLock = NSLock()
        func deliver(_ result: TestCaseResult) {
            guard let test = tests.first(where: { $0.testIdentifier == result.testCaseIdentifier }), emitted.insert(result.testCaseIdentifier).inserted else { return }
            preview(result, test)
        }
        // Final JSON reconciles previews if the transport splits, pads or drops progress chunks.
        _ = try executer.execute(q(worker) + " mendoza run_test_batch " + q(directory + "/request.json"), progress: { chunk in
            progressLock.lock()
            defer { progressLock.unlock() }
            for line in framer.append(Data(chunk.replacingOccurrences(of: "\0", with: "").utf8)) where line.hasPrefix(BatchWorker.previewPrefix) {
                let json = String(line.dropFirst(BatchWorker.previewPrefix.count))
                if let result = try? JSONDecoder().decode(TestCaseResult.self, from: Data(json.utf8)) {
                    deliver(result)
                }
            }
        })
        let completionData = try download(directory + "/completion.json", executer: executer)
        let completion = try JSONDecoder().decode(BatchCompletion.self, from: completionData)
        guard completion.identifier == identifier,
              Set(completion.results.map(\.testCaseIdentifier)).count == completion.results.count,
              Set(completion.unstarted).count == completion.unstarted.count,
              completion.results.count + completion.unstarted.count == tests.count,
              Set(completion.results.map(\.testCaseIdentifier) + completion.unstarted.map(\.testIdentifier)) == Set(tests.map(\.testIdentifier)) else {
            throw Error("Invalid batch completion for \(identifier)")
        }
        progressLock.lock()
        completion.results.forEach(deliver)
        progressLock.unlock()

        let output = try String(decoding: download(directory + "/xcodebuild.log", executer: executer), as: UTF8.self)
        let logDirectory = Path.logs.rawValue + "/batches/" + identifier
        _ = try executer.execute("mkdir -p \(q(logDirectory)) && cp \(q(directory + "/xcodebuild.log")) \(q(directory + "/request.json")) \(q(directory + "/completion.json")) \(q(logDirectory))")
        if let interruption = completion.interruption {
            executer.logger?.log(exception: "Batch \(identifier): \(interruption)")
        }
        if completion.results.allSatisfy({ $0.status == .passed }), completion.exitStatus != 0 || completion.interruption != nil {
            sync.sync { jobErrors.append("Batch \(identifier) did not finalize successfully (exit \(completion.exitStatus), \(completion.interruption ?? "xcodebuild error"))") }
        }
        let analysis = OutputAnalyzer().analyze(output)
        try OutputAnalyzer().assertAccessibilityPermissions(in: output)
        let recovery = SimulatorRecovery(verbose: configuration.verbose)
        if analysis.damagedBuild {
            try recovery.handleDamagedBuild(executer: executer)
        }
        if analysis.requiresSimulatorReset {
            recovery.forceReset(executer: executer, testRunner: runner)
        }
        if analysis.requiresBootstrapWait {
            Thread.sleep(forTimeInterval: 10)
        }

        let hasResult = try executer.fileExists(atPath: resultPath)
        var results = completion.results
        if hasResult {
            if let threshold = configuration.testing.xcresultBlobThresholdKB {
                // A failed cleanup preserves the bundle. The batch cleaner visits every member before deleting blobs.
                let cleaned = try? executer.execute(q(worker) + " mendoza cleanup_batch_xcresult " + q(resultPath) + " " + String(threshold))
                if cleaned?.contains("MENDOZA_BATCH_CLEANED") != true {
                    executer.logger?.log(exception: "Batch blob cleanup skipped; preserving xcresult metadata and attachments")
                }
            }
            for index in results.indices {
                results[index].xcResultPath = resultPath
            }
        } else if results.contains(where: { $0.status == .passed }) {
            throw Error("Batch \(identifier) passed tests but produced no xcresult")
        }

        // Each invocation has its own DerivedData directory: no previous profile can enter this snapshot.
        let files = try CoverageHandler(verbose: false).findCoverageFiles(executer: executer, coveragePath: directory)
        let profile: String?
        if files.isEmpty {
            profile = nil
            let message = "Batch \(identifier) has no coverage profile (started \(completion.started.count) tests, exit \(completion.exitStatus))"
            executer.logger?.log(exception: message)
            if !completion.started.isEmpty {
                sync.sync { jobErrors.append(message) }
            }
        } else {
            let immutable = directory + "/coverage.profdata"
            _ = try executer.execute("xcrun llvm-profdata merge -sparse \(files.map(q).joined(separator: " ")) -o \(q(immutable))")
            // Only the checkpoint lives under Path.logs, the collector's profile sweep root.
            let checkpointDirectory = Path.logs.rawValue + "/batch-checkpoints"
            // Simulator identifiers can repeat on cloned nodes. Globally unique filenames prevent rsync overwrites.
            let checkpoint = sync.sync { () -> String in
                let key = node.address + "/" + runner.id
                if let path = checkpoints[key] {
                    return path
                }
                let path = checkpointDirectory + "/" + UUID().uuidString + ".profdata"
                checkpoints[key] = path
                return path
            }
            _ = try executer.execute("mkdir -p " + q(checkpointDirectory))
            let inputs = try executer.fileExists(atPath: checkpoint) ? [checkpoint, immutable] : [immutable]
            let temporary = checkpoint + ".tmp"
            _ = try executer.execute("xcrun llvm-profdata merge -sparse \(inputs.map(q).joined(separator: " ")) -o \(q(temporary)) && mv \(q(temporary)) \(q(checkpoint))")
            profile = immutable
        }

        let jobResults = results
        // ThreadQueue acquires capacity before the block creates a connection.
        jobs.addOperation { [self] in
            do {
                let background = try executer.clone()
                let logger = ExecuterLogger(name: "BatchArtifacts-" + identifier, address: node.address)
                background.logger = logger
                addLogger(logger)
                if hasResult {
                    do {
                        try background.rsync(sourcePath: resultPath, destinationPath: destinationPath + "/" + runner.id, on: configuration.resultDestination.node)
                        _ = try background.execute("rm -rf " + q(resultPath))
                    } catch {
                        logger.log(exception: "Batch transfer failed; preserving source for collector: \(error)")
                    }
                }
                if let profile {
                    try exportCoverage(profile: profile, identifier: identifier, results: jobResults, completion: completion, worker: worker, executer: background)
                }
                _ = try background.execute("rm -rf " + q(directory))
            } catch {
                sync.sync { jobErrors.append("\(identifier): \(error)") }
            }
        }
        return Outcome(results: results, unstarted: completion.unstarted, requiresQuarantine: completion.started.isEmpty && analysis.isInfrastructureLaunchFailure)
    }

    private func exportCoverage(profile: String, identifier: String, results: [TestCaseResult], completion: BatchCompletion, worker: String, executer: Executer) throws {
        let testing = configuration.testing
        guard testing.extractIndividualTestCoverage || testing.extractTestCoveredFiles else { return }
        let q = Self.quote
        let json = try CodeCoverageGenerator(configuration: configuration, baseUrl: baseUrl).generateJsonCoverage(executer: executer, coverageUrl: URL(fileURLWithPath: profile), summary: true, pathEquivalence: testing.codeCoveragePathEquivalence, strict: true)
        // The legacy exporter uses pipelines. Validate the produced document so an earlier pipeline failure cannot look successful.
        let data = try download(json.path, executer: executer)
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = document["data"] as? [[String: Any]],
              let files = records.first?["files"] as? [[String: Any]], !files.isEmpty else {
            throw Error("Empty or invalid batch coverage report: \(identifier)")
        }
        let coveredFiles = URL(fileURLWithPath: profile).deletingLastPathComponent().appendingPathComponent("covered-files.json").path
        if testing.extractTestCoveredFiles {
            _ = try executer.execute(q(worker) + " mendoza extract_files_coverage " + q(json.path) + " " + q(coveredFiles))
        }
        for (enabled, root, source) in [(testing.extractIndividualTestCoverage, Path.individualCoverage.rawValue, json.path),
                                        (testing.extractTestCoveredFiles, Path.testFileCoverage.rawValue, coveredFiles)] where enabled {
            let canonical = root + "/batches/" + identifier
            _ = try executer.execute("mkdir -p \(q(canonical)) && cp \(q(source)) \(q(canonical + "/coverage.json"))")
            // Membership and interruption status are kept separately from the existing report schema.
            let metadata: [String: Any] = ["scope": "batch", "invocation": identifier,
                                           "members": completion.started.map(\.testIdentifier),
                                           "coverageMayBeIncomplete": completion.interruption != nil || completion.results.contains { $0.status == .failed },
                                           "aliases": results.filter { $0.status == .passed }.map(Self.coverageAlias)]
            try upload(JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), to: canonical + "/metadata.json", executer: executer)
            for result in results where result.status == .passed {
                _ = try executer.execute("cp \(q(source)) \(q(root + "/" + Self.coverageAlias(result)))")
            }
        }
        _ = try executer.execute("rm -f " + q(json.path))
    }

    static func coverageAlias(_ result: TestCaseResult) -> String {
        "\(result.suite)-\(result.name)-\(Int(result.startInterval)).json"
    }

    private func upload(_ data: Data, to path: String, executer: Executer) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)
        try executer.upload(localUrl: url, remotePath: path)
    }

    private func download(_ path: String, executer: Executer) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try executer.download(remotePath: path, localUrl: url)
        return try Data(contentsOf: url)
    }
}
