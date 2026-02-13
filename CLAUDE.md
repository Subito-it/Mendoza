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

## Architecture

### Operation Pipeline

Mendoza uses an **NSOperation-based pipeline** orchestrated by NSOperationQueue. Operations have dependencies ensuring proper execution order:

1. **Initialization**: `InitialSetupOperation` → `ValidationOperation` → `MacOsValidationOperation` → `LocalSetupOperation` → `RemoteSetupOperation`
2. **Compilation**: `TestExtractionOperation` → `CompileOperation` → `TestSortingOperation`
3. **iOS Setup**: `SimulatorSetupOperation` → `ProcessKillerOperation`
4. **Execution**: `DistributeTestBundleOperation` → `TestRunnerOperation`
5. **Collection**: `TestCollectorOperation` → `CodeCoverageCollectionOperation` → `TearDownOperation` → `CleanupOperation` → `SimulatorTearDownOperation`

### Code Organization

```
Sources/mendoza/
├── Commands/           # CLI command implementations
├── Executer/           # Command execution (local/remote SSH)
│   ├── LocalExecuter.swift
│   ├── RemoteExecuter.swift
│   └── ConnectionPool.swift
├── Models/             # Data models (Configuration, Node, Device, TestCase)
├── Operations/         # NSOperation-based pipeline operations
├── Plugins/            # Plugin system (6 types: extract, sorting, event, precompilation, postcompilation, teardown)
├── XCTest/             # XCTest file parsing via SourceKitten
├── xcodeproj/          # Xcode project manipulation
└── CommandLineProxy/   # Wrappers for CLI tools (xcodebuild, simctl, etc.)
```

### Key Abstractions

**BaseOperation<Output>**: All operations inherit from this, providing:
- Typed output passing between operations
- Error handling and logging
- Execution timing/benchmarking
- Per-node environment variables

**Executer Protocol**: Abstraction for local and remote command execution:
```swift
protocol Executer {
    func execute(_ command: String) throws -> String
    func capture(_ command: String) throws -> (status: Int32, output: String)
    func fileExists(atPath: String) throws -> Bool
    func download(remotePath: String, localUrl: URL) throws
    func upload(localUrl: URL, remotePath: String) throws
}
```

### Remote Execution

- SSH/SFTP via libssh2 (Shout wrapper)
- Connection pooling in `ConnectionPool.swift`
- Credentials stored in macOS Keychain via KeychainAccess
- rsync for efficient file transfers

## Plugin System

Plugins are Swift scripts executed via `swift sh`. Six plugin types customize the pipeline:
- **extract**: Custom test method extraction
- **sorting**: Execution time estimates for optimal distribution
- **event**: React to pipeline events
- **precompilation/postcompilation**: Execute before/after compilation
- **teardown**: Execute at end of dispatch

Templates in `/md/`: `TestExtractionPlugin_example.swift`, `TestSortingPlugin_example.swift`

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

## Code Style

- SwiftFormat: 4-space indent, LF line breaks, alphabetized imports
- SwiftLint: See `swiftlint.yml` for enabled rules
