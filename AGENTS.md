# AGENTS.md

Guidance for anyone — human or coding agent — working in this repository. `CLAUDE.md` is a
symlink to this file, so Claude Code and any tool following the `AGENTS.md` convention read
the same content.

## Project Overview

Mendoza is a UI test parallelization tool for iOS and macOS projects written in Swift. It distributes test execution across multiple remote or local machines to reduce testing time by:
1. Compiling a project using xcodebuild's `build-for-testing`
2. Distributing the compiled test bundle to multiple remote nodes
3. Executing subsets of tests on each node (multiple simulators per node for iOS)
4. Collecting and merging results into a single `.xcresult` bundle

## Important Constraints

- **Do not use Swift 6 features or Swift Concurrency (async/await, actors, etc.)**. The codebase uses NSOperation-based concurrency patterns.
- Swift tools version: 5.8
- Platform: macOS 13.0+

## Build Commands

```bash
# Prerequisites
brew install libssh2 openssl@3

# Build (debug)
swift build

# Build (release)
swift build -c release

# Run tests
swift test

# Lint
swiftlint

# Format code
swiftformat .
```

## Code Style

- SwiftFormat: 4-space indent, LF line breaks, alphabetized imports
- SwiftLint: See `swiftlint.yml` for enabled rules

## Main Commands

```bash
# Execute UI tests (iOS)
mendoza test --project MyApp.xcodeproj --scheme MyAppUITests --device_name "iPhone 15" --device_runtime "17.0"

# Execute UI tests (remote nodes)
mendoza test --project MyApp.xcodeproj --scheme MyAppUITests --remote_nodes_configuration nodes.json

# Generate node configuration
mendoza configuration init

# Show a plugin's input envelope and expected output
mendoza plugin describe TearDownPlugin
```

---

# Documentation Conventions

## `README.md` documents current behaviour

The README describes how Mendoza behaves **now**, and every section must stand on its own.
Do not write anything whose meaning depends on the reader knowing an earlier version:

- no "X is no longer Y", "X used to Z", "the previous default was W"
- no before/after `diff` blocks contrasting an old invocation with a new one
- no reference to a default that is not itself documented in the README

A reader arriving at the README has never run an older release, so delta framing is simply
unreadable to them. When a change alters behaviour, document only the resulting state and
put the migration story in the GitHub release notes for that version.

```
# wrong — requires knowing what came before
## Build settings are no longer overridden
Mendoza used to append `SWIFT_OPTIMIZATION_LEVEL='-Osize'` to every build…

# right — describes the current state
Nothing is set by default, so your project's own build configuration is honoured.
```

Documenting a mechanic a user can trip over is reference material, not a delta, and belongs
in the README — for example "if you pass the individual Watch services without
`nanoregistrylaunchd`, every run pays an extra simulator reboot". The test is whether
understanding the sentence requires knowing an older Mendoza.

The existing `# Migrating to 27.0.0` section is a deliberate exception carrying the plugin
system rewrite, a breaking change to a documented public contract. It is not licence to log
every behaviour change there; an undocumented internal default has no prior contract to
migrate from.

## Keep tracked docs free of downstream specifics

This repository is public and Mendoza is consumed by projects that are not. Tracked files —
`README.md`, `AGENTS.md`, `docs/` — must not identify the project a change was developed or
measured against. That covers the obvious cases (internal hostnames, IP addresses, SSH
users, private repository paths, CI URLs) and the easily missed ones:

- localized UI strings copied from a failing test
- real test, suite, target or scheme names
- app, screen or feature names

Describe the observable symptom in neutral terms instead. "Disabling it leaves the share
sheet empty, breaking the system Copy action in any app that presents one" carries the same
technical information as a quote from a specific app's UI, without pinning it to a product.

Use illustrative placeholders in examples — `localhost`, `SomeProject.xcworkspace`,
`/path/to/…`, generic script names.

Working documents (implementation plans, reverse-engineering notes, investigation
write-ups) belong in `notes/`, which is gitignored. Do not reference `notes/` from a tracked
file: a pointer to a document that is not in the repository is itself a signal about what
exists elsewhere.

## Keep docs in sync with the catalogs they mirror

Several README tables restate values defined in code — most notably the simulator service
groups in `Sources/mendoza/Models/SimulatorService.swift`, mirrored in the README's
`--disable_sim_services` table and in `docs/ios27-simulator-services.md`. Editing a group
means editing the matching table in the same change, otherwise the docs go stale without any
test failing.

---

# Detailed Architecture Documentation

## Code Organization

```
Sources/mendoza/
├── Commands/              # CLI command implementations (Bariloche framework)
│   ├── Test/              # Main test command and orchestration
│   ├── Configuration/     # Remote node configuration commands
│   ├── Simulator/         # Simulator service and window subcommands
│   ├── Plugins/           # `plugin describe` and plugin type listing
│   └── Mendoza/           # Root command wiring
├── Executer/              # Command execution abstraction
│   ├── Executer.swift     # Protocol definition
│   ├── LocalExecuter.swift
│   ├── RemoteExecuter.swift
│   └── ConnectionPool.swift
├── Models/                # Data models
├── Operations/            # NSOperation-based pipeline stages
├── Plugins/               # Plugin system (6 types)
├── XCTest/                # Test discovery via SourceKitten
├── xcodeproj/             # Xcode project parsing
├── CommandLineProxy/      # CLI tool wrappers (xcodebuild, simctl)
├── CoreSimulator/         # Private CoreSimulator framework access, window management
├── Logging/               # HTML log generation
├── Swift/                 # Foundation and Bariloche extensions
└── Shared/                # Utilities and validators
```

## Core Abstractions

### 1. BaseOperation<Output> (`Operations/BaseOperation.swift`)

All pipeline operations inherit from `BaseOperation<T>`, which conforms to multiple protocols:

```swift
class BaseOperation<Output>: Operation,
    StartingOperation,      // didStart callback
    EndingOperation,        // didEnd callback with typed Output
    ThrowingOperation,      // didThrow error callback
    LoggedOperation,        // logger accessors
    BenchmarkedOperation,   // timing metrics
    EnvironmentedOperation  // per-node env vars
```

**Key capabilities:**
- Generic over output type for type-safe data passing
- Factory methods: `makeConnectionPool()`, `makeLocalExecuter()`, `makeRemoteExecuter()`
- Automatic timing via KVO on `isExecuting`
- Thread-safe logger management via `syncQueue`

**Data flow pattern:**
```swift
testExtractionOperation.didEnd = { testCases in
    testSortingOperation.testCases = testCases
}
```

### 2. Executer Protocol (`Executer/Executer.swift`)

Abstraction for local and remote command execution:

```swift
protocol Executer: AnyObject {
    var address: String { get }
    var homePath: String { get }
    var environment: [String: String] { get }
    var logger: ExecuterLogger? { get set }

    func execute(_ command: String) throws -> String
    func capture(_ command: String) throws -> (status: Int32, output: String)
    func fileExists(atPath: String) throws -> Bool
    func download(remotePath: String, localUrl: URL) throws
    func upload(localUrl: URL, remotePath: String) throws
    func clone() throws -> Self
    func terminate()
}
```

**Implementations:**
- `LocalExecuter`: Uses Foundation's `Process` for shell commands
- `RemoteExecuter`: Uses libssh2 (Shout wrapper) for SSH/SFTP

### 3. ConnectionPool<T> (`Executer/ConnectionPool.swift`)

Generic pool for parallel execution across nodes:

```swift
class ConnectionPool<SourceValue> {
    struct Source<Value> {
        let node: Node
        let value: Value          // Associated data (e.g., Simulator)
        let environment: [String: String]
        let logger: ExecuterLogger?
    }

    func execute(block: @escaping (Executer, Source<SourceValue>) throws -> Void) throws
}
```

Spawns concurrent operations per source using `ThreadQueue` (NSOperationQueue wrapper). Tracks `startIntervals` and `endIntervals` per node for benchmarking.

### 4. Thread Safety Patterns

Since the codebase **does not use Swift Concurrency**:

- **DispatchQueue (serial)**: Protects mutable state
  ```swift
  private let syncQueue = DispatchQueue(label: "...")
  syncQueue.sync { self.mutableProperty = value }
  ```
- **NSCountedSet**: Thread-safe counting (e.g., `retryCountMap`)
- **ThreadQueue**: Wrapper around NSOperationQueue for parallel work

## Operation Pipeline

### Pipeline DAG (Dependency Order)

Defined in `Commands/Test/Test+MakeOperations.swift:82-116`:

```
InitialSetupOperation
    ↓
├── ValidationOperation → RemoteSetupOperation
├── MacOsValidationOperation (cancelled for iOS)
└── LocalSetupOperation
        ↓
    ├── CompileOperation → DistributeTestBundleOperation
    └── TestExtractionOperation → TestSortingOperation
                                        ↓
SimulatorSetupOperation ────────────────┤
        ↓                               │
ProcessKillerOperation (optional)       │
                                        ↓
                            TestRunnerOperation
                                    ↓
                            TestCollectorOperation
                                    ↓
                    ├── CodeCoverageCollectionOperation
                    └── SimulatorTearDownOperation
                                    ↓
                            CleanupOperation
                                    ↓
                            TearDownOperation
```

### Key Operations

#### TestRunnerOperation (`Operations/TestRunnerOperation.swift`)

Core test execution engine implementing **work-stealing queue** pattern:

1. **Input**: `sortedTestCases` (by estimated duration), `testRunners` (simulators/nodes)
2. **Execution loop** (per runner):
   ```swift
   while true {
       testCase = syncQueue.sync { nextTestCase() }  // Atomic dequeue
       if testCase == nil {
           if allRunnersCompleted { break }
           Thread.sleep(1.0)  // Wait for retries
           continue
       }
       // Execute via TestExecuter, handle results
   }
   ```
3. **Retry logic**: Failed tests re-enqueued at position 1 (runs on different simulator)
4. **Progressive coverage merge**: Merges each invocation's immutable `.profdata` into a per-runner checkpoint

#### TestExecuter (`Operations/TestRunnerOperation/TestExecuter.swift`)

Executes one or two selected tests per xcodebuild invocation through the node-local worker.
Both batch sizes share the same executor, watchdog, and coverage pipeline. The worker
uses an isolated DerivedData directory and one explicit result bundle per invocation:

```swift
xcodebuild -parallel-testing-enabled NO \
    -xctestrun '{scheme}.xctestrun' \
    -destination 'platform=iOS Simulator,id={uuid}' \
    -only-testing:'{target}/{suite}/{test}' \
    -enableCodeCoverage YES \
    test-without-building
```

**Features:**
- Parses stdout for test start/pass/fail/crash events via regex
- Preview callback fires immediately on test completion (before xcresult finalized)
- Worker phase watchdogs and process-group cancellation terminate hung invocations
- Handles: accessibility failures, preflight failures, damaged builds, crashes

#### DistributeTestBundleOperation

Uses **tree-based propagation** for O(log N) distribution:

```
Compilation Node → Node A → Node C
                 → Node B → Node D
```

Any node with the bundle becomes a source for others.

#### SimulatorSetupOperation (`Operations/SimulatorSetupOperation.swift`)

For iOS testing:
1. Determines runner count: `physicalCPUs / 2` (auto) or manual
2. Creates named simulators: `{DeviceName}-1`, `{DeviceName}-2`, etc.
3. Configures settings (keyboard, graphics, locale, bezel)
4. Arranges windows in grid layout
5. Boots in parallel with Xcode-version-specific workarounds
6. Auto-deletes simulators on low disk space

Settings that live in the device's preference plists are written **before** boot, because
`cfprefsd` owns those domains while the device is running and rewrites them from memory.
Each writer reports whether it changed anything, and those results feed a single
`rebootRequired` decision rather than each triggering its own reboot.

#### TestCollectorOperation (`Operations/TestCollectorOperation.swift`)

1. Collects `.profdata` and `.xcresult` files from all nodes via rsync
2. **Batch merging**: Splits xcresults into ~50-result batches, merges in parallel
3. Final merge using `xcrun xcresulttool merge`

## Simulator Service Slimming

`--disable_sim_services` disables background daemons inside each booted simulator to reclaim
RAM on memory-constrained nodes. `Models/SimulatorService.swift` holds the catalog: a list of
known-safe services plus named groups that expand to them.

Key facts that are not obvious from the code:

- Overrides are applied with `launchctl disable` via `simctl spawn`, and only persist across
  reboots on **iOS 18+**. The feature is gated on the runtime version.
- `launchctl print-disabled` reports only *overrides*, never a job's own plist-level
  `Disabled` default. A label absent from that output therefore has **no override**, which is
  not the same as being enabled. Use `plutil -extract Disabled raw` on the job's plist to
  learn whether a service actually runs.
- `launchctl disable` only prevents future launches, so a reboot is required to stop daemons
  that are already running.
- Some services are only kept alive by another service that enables them, and disabling those
  individually never holds. The Watch companion family is the known case: every daemon in
  `/System/Library/NanoLaunchDaemons` ships disabled in its own plist and runs only because
  `nanoregistrylaunchd` enables the whole directory on demand, after any boot-readiness wait
  has returned. Disabling the enabler is what sticks.
- A handful of daemons wedge the simulator or hang every subsequent `simctl` call when
  disabled. `Tests/mendozaTests/SimulatorServiceTests.swift` keeps a `forbiddenLabels` set
  asserting they never enter the catalog — read it before adding a service.

## Key Data Models

### TestCase (`Models/TestCase.swift`)

```swift
struct TestCase: Codable, Hashable {
    let name: String      // Method name (e.g., "testLogin")
    let suite: String     // Class name (e.g., "LoginTests")
    var testIdentifier: String { "\(suite)/\(name)" }
}
```

### TestCaseResult (`Models/TestCaseResult.swift`)

```swift
struct TestCaseResult: Codable {
    var node: String              // Node address
    var runnerName: String        // Simulator name
    var runnerIdentifier: String  // Simulator UUID
    var xcResultPath: String
    var suite: String
    var name: String
    var status: Status            // .passed or .failed
    var startInterval: TimeInterval
    var endInterval: TimeInterval
    var duration: TimeInterval { endInterval - startInterval }
}
```

### Configuration (`Models/Configuration.swift`)

```swift
struct Configuration: Codable {
    let building: Building      // projectPath, scheme, sdk, buildConfiguration
    let testing: Testing        // timeouts, retries, coverage settings
    let device: Device?         // name, runtime, language, locale (iOS only)
    let plugins: Plugins?       // custom data, replay path
    let resultDestination: ConfigurationResultDestination
    let nodes: [Node]
    let verbose: Bool
}
```

`Building.Settings.buildSettings` is appended verbatim to the `build-for-testing` command
line, which outranks every xcconfig, target and configuration value in the user's project. It
is empty by default so the project's own build configuration is honoured; only the caller
should decide to override it, via `--build_settings`.

## Test Discovery

### XCTestFileParser (`XCTest/XCTestFileParser.swift`)

Uses SourceKittenFramework to parse Swift source files:

1. Parses AST structure via `Structure(file:)`
2. Iterates 5 times to resolve class inheritance chains
3. Finds classes inheriting from `XCTestCase`
4. Extracts methods matching `isTestMethod` (starts with "test", no parameters)

## Plugin System

### Plugin Types (`Plugins/`)

| Plugin | Input | Output | Purpose |
|--------|-------|--------|---------|
| `TestExtractionPlugin` | `TestExtractionInput` | `[TestCase]` | Custom test discovery |
| `TestSortingPlugin` | `TestOrderInput` | `[TestCase]` | Execution time estimates |
| `EventPlugin` | `EventPluginInput` | `PluginVoid` | React to pipeline events |
| `PreCompilationPlugin` | `PluginVoid` | `PluginVoid` | Pre-compile actions |
| `PostCompilationPlugin` | `PostCompilationInput` | `PluginVoid` | Post-compile actions |
| `TearDownPlugin` | `TestSessionResult` | `PluginVoid` | Cleanup actions |

### Plugin Execution (`Plugins/Plugin.swift`)

A plugin is any executable named after the plugin type (no extension, executable bit set) at
`pluginUrl`. It is run via its own shebang and communicates over standard streams:

1. Encodes `{input, data}` into a single JSON envelope. `input` is `{}` for
   `PluginVoid` inputs; `data` is null when the plugin data string is empty
2. Dumps the envelope to `<name>.<timestamp>.json` (`0600`) on every invocation, under
   `--plugin_replay_path` or the session logs, so failures are reproducible with
   `cat envelope | plugin`
3. Spawns the executable directly, writing the envelope to **stdin off-thread** (a plugin
   that ignores stdin, or writes a lot to stdout first, would otherwise deadlock) with
   stderr redirected to a temp file (two pipes drained sequentially deadlock)
4. Always waits, then decodes the **entire** stdout as `Output` — unless `Output` is
   `PluginVoid`, in which case stdout is ignored. Non-zero exit throws with stderr attached

`main.swift` ignores `SIGPIPE`: without it, writing to a plugin that exited early would
terminate Mendoza. Concurrent invocations are expected (one `EventPlugin` instance is shared
across the pipeline), so in-flight processes are tracked under a serial queue.

## Remote Execution

### RemoteExecuter (`Executer/RemoteExecuter.swift`)

- SSH via libssh2 (Shout wrapper)
- Authentication: agent, password, or key-based
- SFTP for file transfers
- Commands wrapped: `bash -c "..."`
- Environment exports prepended to commands

### rsync Usage (`Executer/Executer+Rsync.swift`)

```swift
rsync -az -e "ssh -o StrictHostKeyChecking=no -c aes128-gcm@openssh.com" \
    --include='*/' --include='*.profdata' --exclude='*' \
    source/ user@host:destination/
```

Optimizations: fast cipher, selective includes/excludes.

## Logging System

### ExecuterLogger (`Logging/ExecuterLogger.swift`)

Per-operation HTML logs capturing:
- Commands executed with timestamps
- Output and exit codes
- Errors highlighted in red
- Sensitive data redaction

Structure:
```swift
struct LoggerEvent {
    enum Kind {
        case start(command: String)
        case end(output: String, statusCode: Int32)
        case exception(error: String)
    }
    let date: Date
    let kind: Kind
}
```

## Error Handling

### Centralized (`Commands/Test/Test.swift`)

```swift
operations.compactMap { $0 as? ThrowingOperation }.forEach { op in
    op.didThrow = { error in
        op.logger.log(exception: error.localizedDescription)
        self.tearDown(operations: operations, testSessionResult: testSessionResult, error: error)
    }
}
```

### Operation Cancellation

Cancels from leaves to root to prevent race conditions:
```swift
while completedOperations.count != operations.count {
    for operation in operations {
        let dependingOperations = operations.filter { $0.dependencies.contains(operation) }
        if dependingOperations.allSatisfy(\.isCancelled) {
            operation.cancel()
            completedOperations.insert(operation)
        }
    }
}
```

## File Paths (Constants)

Defined in `Path` enum (`Operations/BaseOperation.swift`):

| Path | Value | Purpose |
|------|-------|---------|
| `.base` | `/tmp/mendoza` | Root temp directory (`Environment.temporaryBasePath`) |
| `.build` | `base/build` | Compilation output |
| `.testBundle` | `build/Build/Products` | .xctest bundle |
| `.logs` | `base/logs` | Per-operation HTML logs |
| `.results` | `base/results` | Per-runner xcresults |
| `.temp` | `base/tmp` | Scratch space |
| `.coverage` | `base/coverage` | Merged coverage |
| `.individualCoverage` | `base/individual_coverage` | Per-test coverage JSONs |
| `.testFileCoverage` | `base/test_file_coverage` | Per-test covered files |
