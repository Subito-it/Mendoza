# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

# Generate plugin template
mendoza plugin init
```

---

# Detailed Architecture Documentation

## Code Organization

```
Sources/mendoza/
├── Commands/              # CLI command implementations (Bariloche framework)
│   ├── Test/              # Main test command and orchestration
│   ├── Configuration/     # Remote node configuration commands
│   └── Plugins/           # Plugin initialization commands
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
├── Logging/               # HTML log generation
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

Defined in `Commands/Test/Test.swift:127-156`:

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
4. **Progressive coverage merge**: Merges `.profdata` after each test for efficiency

#### TestExecuter (`Operations/TestRunnerOperation/TestExecuter.swift`)

Executes single test via xcodebuild:

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
- Stdout timeout handler terminates hung tests
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

#### TestCollectorOperation (`Operations/TestCollectorOperation.swift`)

1. Collects `.profdata` and `.xcresult` files from all nodes via rsync
2. **Batch merging**: Splits xcresults into ~50-result batches, merges in parallel
3. Final merge using `xcrun xcresulttool merge`

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
    let plugins: Plugins?       // custom data, debug flag
    let resultDestination: ConfigurationResultDestination
    let nodes: [Node]
    let verbose: Bool
}
```

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
| `TearDownPlugin` | `TearDownInput` | `PluginVoid` | Cleanup actions |

### Plugin Execution (`Plugins/Plugin.swift`)

1. Copies plugin script with SHA256 suffix (cache key)
2. Appends runner code for JSON serialization
3. Executes: `./Plugin.swift '<json_input>' '<plugin_data>'`
4. Parses output after `# plugin-result` marker

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
| `.base` | `~/.mendoza` | Root temp directory |
| `.build` | `base/build` | Compilation output |
| `.testBundle` | `build/Build/Products` | .xctest bundle |
| `.logs` | `base/logs` | Per-operation HTML logs |
| `.results` | `base/results` | Per-runner xcresults |
| `.coverage` | `base/coverage` | Merged coverage |
| `.individualCoverage` | `base/individual_coverage` | Per-test coverage JSONs |
| `.testFileCoverage` | `base/test_file_coverage` | Per-test covered files |

## Related Documentation

- **`CODECOVERAGE_EXTRACTION.md`**: Analysis of individual test coverage extraction, known issues with cumulative coverage, and proposed fixes
