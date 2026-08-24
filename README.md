# 🍷 Mendoza 

Mendoza is a tool designed to offer a more flexible approach to UI Tests parallelization. It allows to dispatch tests execution on an unlimited number of remote machines significantly reducing the time required to run your test suites.

The tools functionality can be extended by adding [plugins](#Plugins) allowing to heavily customize several steps in the dispatching pipeline.

The outcome of a test session will be a set of log files (.json, .html) and a single .xcresult bunble that will contain all results as if all tests were run on a single machine.

A snapshot of a session running on 8 concurrent nodes (each running 2 simulators at once) can be seen below.

<img src='md/running.png' width='724'>


|       | Features                             |
| :---: | ------------------------------------ |
|   🏃‍♀️   | Makes UI Test execution super fast!  |
|   👨🏻‍💻   | Written in Swift                     |
|   🔌   | Supports plugins (in any language)   |
|   🔍   | Wide set of result formats           |
|   🤖   | Supports both iOS and macOS projects |

While the tool is particularly designed for remote execution it enhances local execution as well.


# How does it work

The basic idea is simple: you compile a project on one machine, distribute the compiled package (test bundle) to a number of specified remote nodes, execute a subset of tests on each node and collect the results back together as if they were run on a single machine. On iOS projects, depending on the node hardware configuration, you can also run multiple simulators at once.

Mendoza hides all the complexity behind a single `test` command by leveraging built in command line tools to perform each of the aforementioned steps. To get an idea of what’s under the hood take a look [here](md/under-the-hood.md).



# Installation

You'll need to install Mendoza on all nodes you'll use to distribute tests.

```
brew install Subito-it/made/mendoza
```

> **NOTE**
> 
> You'll get a warning that sshpass was removed for security reasons. You can still install a copy by running `brew install hudochenkov/sshpass/sshpass` see [repo](https://github.com/hudochenkov/homebrew-sshpass). Please consider that sshpass is used only if you choose to connect to remote nodes via username/password authentication which is not the recommended way. When possible you should use ssh key based authentication.



Or you can build manually from sources

## Building from sources

To build Mendoza make sure to install libssh2:
```
brew install libssh2
git clone https://github.com/Subito-it/Mendoza.git
cd Mendoza
swift package update
swift package generate-xcodeproj
xed .
```

From the target selection select the Mendoza project and add `/usr/local/include` to 'Header Search Paths' and `/usr/local/lib` to 'Library Search Paths'.

# Migrating to 27.0.0

27.0.0 replaces the plugin system and changes two things about how `test` is invoked. If you don't use plugins, only [Test diagnostics](#test-diagnostics-collection) affects you.

## Plugins are now executables, not Swift scripts

Previously a plugin was a `.swift` file containing a struct with a `handle()` method. Mendoza appended a runner to it, compiled it with `#!/usr/bin/swift`, and passed the input as two positional arguments. Now a plugin is **any executable in any language**: Mendoza writes one JSON envelope to its stdin and reads the result from its stdout.

| | Before | Now |
| --- | --- | --- |
| File name | `TearDownPlugin.swift` | `TearDownPlugin` (no extension) |
| Language | Swift only | anything with a shebang, or a compiled binary |
| Executable bit | set by Mendoza | **you** must `chmod +x` |
| Input | two `argv` entries: input JSON, then plugins data | one JSON envelope on stdin: `{"input": …, "data": …}` |
| Output | stdout after a `# plugin-result` marker | the whole of stdout |
| Diagnostics | mixed into stdout | stderr, captured into the session log |
| Dependencies | [swift sh](https://github.com/mxcl/swift-sh) | whatever your language already uses |

To port an existing plugin:

1. rename the file to drop `.swift`, and `chmod +x` it
2. read the envelope from stdin instead of `argv`, taking `input` and `data` from it
3. print only the result to stdout, and move any logging to stderr

Run `mendoza plugin describe <PluginName>` to print the exact envelope your plugin will receive along with a starter script. The output is generated from Mendoza's own types, so it always matches the version you are running. See [Plugins](#plugins) for the full contract.

Because the two systems share no surface, a plugin that has not been ported is not silently ignored: `TestExtractionPlugin` and `TestSortingPlugin` fail the session, and the remaining plugins are skipped.

### `EventPlugin`: `kind` is now a string

`Event.Kind` was encoded as an integer, so its values depended on declaration order. It is now the case name:

```diff
- {"kind": 2, "info": {}}
+ {"kind": "startCompiling", "info": {}}
```

If you were switching on `0`, `1`, `2`… switch on `"start"`, `"stop"`, `"startCompiling"`, `"stopCompiling"`, `"startTesting"`, `"stopTesting"` and `"error"` instead.

`TearDownPlugin`'s input is unchanged, including `status` as `0` for passed and `1` for failed.

### `plugin init` is gone

Plugin templates were generated by `plugin init`. Use [`plugin describe`](#plugin-describe) instead, which prints the envelope and a starter script for a given plugin without writing anything to disk.

## `--plugin_debug` is now `--plugin_replay_path`

`--plugin_debug` took no value and kept Mendoza's intermediate files next to your plugins. It has been removed, so a command line still passing it now fails to parse.

Every invocation now dumps its stdin envelope as `<PluginName>.<timestamp>.json` with no flag required, so replaying a failure is always possible after the fact. `--plugin_replay_path <path>` only chooses **where**, the default being the session logs folder, which is wiped when the next session starts:

```diff
- mendoza test … --plugin_debug
+ mendoza test … --plugin_replay_path ./mendoza-replay
```

See [Debugging plugins](#debugging-plugins) for the replay loop.

## Test diagnostics are no longer collected by default

Mendoza now always passes `-collect-test-diagnostics never` to `xcodebuild`, where previously it passed nothing and `xcodebuild` fell back to the value in your test plan. If your test plan enabled diagnostics and you rely on the sysdiagnoses and log archives in the `.xcresult`, pass `--collect_test_diagnostics_on_failure` to restore the old behaviour — and read [Test diagnostics collection](#test-diagnostics-collection) first, because it is slow enough to matter. Crash reports are collected either way.

# Quick start - Local execution

#### iOS project

```
mendoza test --project SomeProject.xcworkspace --scheme SomeScheme --local_destination_path=/Users/SomeUser/Desktop --device_name="iPhone 8" --device_runtime="12.1"
```

#### macOS project

```
mendoza test --project SomeProject.xcworkspace --scheme SomeScheme --local_destination_path=/Users/SomeUser/Desktop

```

This will compile your project, distribute the test bundles, execute the tests, collect the results together on the _destination_ node that was specified during setup and generate a set of [output files](#test-output).


# Quick start - Remote execution

Inside your project folder run

```
mendoza configuration init
```

this will prompt you with a series of (fairly self-explanatory) questions and produce a configuration file that you will feed to the `test` command as follows:


#### iOS project

```
mendoza test --project SomeProject.xcworkspace --scheme SomeScheme --remote_nodes_configuration configuration_file_generated_above.json --device_name="iPhone 8" --device_runtime="12.1"
```

#### macOS project

```
mendoza test --project SomeProject.xcworkspace --scheme SomeScheme --remote_nodes_configuration configuration_file_generated_above.json

```

This will compile your project, distribute the test bundles, execute the tests, collect the results together on the _destination_ node that was specified during setup and generate a set of [output files](#test-output).



# Commands

## `configuration init`

Generates a new configuration file required to execute tests remotely. you will be prompted with a series of (fairly self-explanatory) questions which will produce a json configuration file as an output.

### Concepts

#### Nodes configuration

When setting up nodes you'll be asked:

- label that identifies the node
- address
- authentication method

*iOS projects only*
- concurrent simulators: manually enter the number of concurrent simulators to use at once. The rule of thumb is that you can run 1 simulator per physical CPU core. Specifying more that one simulator per core will work but this will result in slower total execution time because the node will be over-utilized.

#### Destination node

The destination node is the node that will be responsible to collect all the result logs.

## configuration authentication

The credentials and passwords you will be asked during initialization are stored locally in your Keychain (see [configuration file and security](#Configuration-file-and-security) paragraph). This means that if the configuration was generated on a different machine you may be missing those credentials/passwords. The `configuration authentication` command will prompt and store missing credentials/password in your local Keychain.

## `plugin describe`

Prints the JSON envelope a plugin receives on stdin and the output it is expected to write on stdout, together with a minimal starter script. The sample is generated from Mendoza's own types, so it always matches the version of Mendoza you are running.

```sh
mendoza plugin describe TearDownPlugin
```

## `test`

Will launch tests as specified in the configuration files.

### Test diagnostics collection

By default Mendoza passes `-collect-test-diagnostics never` to `xcodebuild`, which disables the collection of verbose diagnostics (sysdiagnoses, log archives).

You can opt back in with `--collect_test_diagnostics_on_failure`, but be aware that this has a **significant performance impact on test dispatching**. When a test fails, `xcodebuild` invokes `simctl diagnose` with a 600 seconds timeout, gathering several hundred megabytes of data into the `.xcresult`. This happens *after* the test verdict has already been reported, and the simulator is kept out of rotation for the entire collection: a single failure can therefore idle a simulator for up to 10 minutes, and with retries enabled the cost is paid on every attempt.

Note that when the flag isn't specified `xcodebuild` would otherwise fall back to the value defined in the test plan, so Mendoza always passes the parameter explicitly to keep dispatch times predictable.

Crash reports are collected by Mendoza independently of this setting.

### Test output

Mendoza will write a set of log files containing information about the test session:

- test_details.json: provides a detailed insight of the test session
- test_result.json: the list of tests that passed/failed in json format
- test_result.html: the list of tests that passed/failed in html format
- repeated_test_result.json: the list of tests that had to be repeated in json format
- repeated_test_result.html: the list of tests that had to be repeated in html format
- merged.xcresult: the result bundle containing all test data. Can be opened with Xcode
- coverage.json: the coverage summary file generated by running `xcrun llvm-cov export --summary-only -instr-profile [path] [executable_path]
- coverage.html: the coverage html file generated by running `xcrun llvm-cov show --format=html -instr-profile [path] [executable_path]

If you're interested in seeing the specific actions that made a test fail can manually inspect the merged.xcresult using Xcode. Alternatively you may also consider using [Cachi](https://github.com/Subito-it/Cachi) which is able to parse and present results in a web browser.


# Plugins

Plugins allow to customize various steps of Mendoza's pipeline. This opens up to several optimizations that are stricly related to your own specific workflows. 

A plugin is **any executable file** — Ruby, Python, bash, a compiled binary, anything with a shebang. Mendoza writes a single JSON envelope to its **stdin** and reads the result from its **stdout**, so nodes need nothing installed beyond whatever your plugin itself requires.

| Channel | Carries |
| --- | --- |
| **stdin** | one JSON envelope (below) |
| **stdout** | the result as JSON, or nothing for plugins that return no value |
| **stderr** | your logs and diagnostics, captured into the session's HTML log |
| **exit code** | `0` on success. Anything else fails the session, with stderr attached to the error — except for `EventPlugin`, whose failures are [deliberately ignored](#debugging-plugins) |

The envelope always carries the same two keys:

```json
{
  "input": { },
  "data": "…"
}
```

- `input` is the plugin's typed input. It is `{}` for plugins that take none.
- `data` is the `--plugins_data` string, passed verbatim and never parsed by Mendoza. It is `null` when unset.

Run `mendoza plugin describe <name>` to see the exact envelope and expected output for a given plugin.

### Installing a plugin

Three things must be true for a plugin to run:

1. the file is named **exactly** after the plugin type, with **no extension**: `TestExtractionPlugin`, `TestSortingPlugin`, `EventPlugin`, `PreCompilationPlugin`, `PostCompilationPlugin`, `TearDownPlugin`
2. it lives at the folder passed as `--plugins_path` (defaulting to the folder containing your configuration file)
3. it is executable — `chmod +x`. Mendoza will not set the bit for you

Get the first two wrong and the plugin is simply not found, which Mendoza treats differently depending on whether it needed a value from it:

- `TestExtractionPlugin` and `TestSortingPlugin` **fail the session**, since Mendoza cannot substitute a result for the one it asked for
- the other four are **skipped silently**, and the pipeline runs as if you had never installed one

A file that is found but not executable always fails the session, with the `chmod +x` to run. That asymmetry is deliberate: a misnamed file is indistinguishable from a plugin you chose not to install, while a missing executable bit is unambiguously a mistake.

### A complete plugin

```ruby
#!/usr/bin/env ruby
require "json"

# Mendoza always writes the envelope to stdin. Accepting a file path as well costs one line
# and makes the plugin runnable under a debugger — see below.
payload = JSON.parse(ARGV[0] ? File.read(ARGV[0]) : $stdin.read)
input   = payload["input"]
data    = JSON.parse(payload["data"] || "{}")

warn "considering #{input["candidates"].size} files"   # diagnostics go to stderr

tests = decide_tests(input, data)

# stdout is the result, decoded by Mendoza as [TestCase]
puts JSON.generate(tests.map { |t| { "name" => t.name, "suite" => t.suite } })
```

Never `print`/`puts` anything but the result: stdout **is** the result.

The following plugins are available:

- `TestExtractionPlugin`: allows to specify the test methods that should be performed in every test file
- `TestSortingPlugin`: plugin to add estimated execution time to test cases
- `EventPlugin`: plugin to perform actions (e.g. notifications) based on dispatching events
- `PreCompilationPlugin`: plugin to perform actions before compilation starts
- `PostCompilationPlugin`: plugin to perform actions after compilation completes
- `TearDownPlugin`: plugin to perform actions at the end of the dispatch process


## TestExtractionPlugin

By default test methods will be extracted from all files in the UI testing target. This should work most of the times however in some advanced cases this could not be the desired behaviour, for example if there is some custom tagging to run tests on specific devices (e.g. only iPhone/iPad). This plugin allows to override the default behaviour and put in place a custom implementation

See an example [TestExtractionPlugin](md/TestExtractionPlugin_example.rb).


## TestSortingPlugin

By default test cases will be executed randomly because Mendoza has no information about the execution time of test cases. Mendoza can significantly improve total execution time of test if you provide an estimate of the execution time of tests.

Using tools like [Cachi](https://github.com/Subito-it/Cachi) you can automatically store and retrieve tests statistics.

See an example [TestSortingPlugin](md/TestSortingPlugin_example.rb).


## EventPlugin

This plugin will be invoked during the different steps of Mendoza's pipeline. You'll be notified when compilation starts/ends, when tests bundles start/end being distributed and so on. Based on these event you could for example send notifications.


## PreCompilationPlugin

Your project might be so heavily customized that you might need to perform some changes to the project before the compilation of the UI testing target begins.


## PostCompilationPlugin

If you're using a precompilation plugin you might also need a post compilation plugin to restore any change previously made.


## TearDownPlugin

This plugin allows to perform custom actions once the test session ends. You'll get some result information as input in order to perform action accoring to the test session outcome



## Debugging plugins

Because a plugin's entire input is one JSON document on stdin, you can replay a real invocation offline instead of running a test session for every change.

**Every** invocation writes its envelope to `<PluginName>.<timestamp>.json`, with no flag required. That is deliberate: you usually discover you want the input *after* the run that misbehaved, and a `TearDownPlugin` envelope — that session's specific pass/fail/retry set — cannot be reconstructed on demand. When a plugin fails, the error tells you how to replay it:

```
🔌 TearDownPlugin failed with status code 1
undefined method `dig' for nil:NilClass (teardown_notify.rb:42)
To reproduce: cat '/tmp/mendoza/logs/TearDownPlugin.20260820-154512.482.json' | '/path/to/plugins/TearDownPlugin'
```

By default envelopes land in the session logs folder, which is **wiped when the next session starts**. Pass `--plugin_replay_path` to keep them somewhere durable — a folder your CI can archive, or one you can point a debugger at:

```sh
mendoza test … --plugin_replay_path ./mendoza-replay
```

So the loop is:

```sh
# 1. keep a real envelope as a fixture
cp ./mendoza-replay/TearDownPlugin.20260820-154512.482.json fixtures/teardown.json

# 2. iterate in a second, without Mendoza
cat fixtures/teardown.json | ./TearDownPlugin
```

One file is written per invocation, timestamped to the millisecond, so a plugin invoked repeatedly during a session — like `EventPlugin` — leaves one envelope per event rather than overwriting itself.

For the plugins that return a value, check the shape of what you print as well as the values, since a result Mendoza cannot decode fails the session:

```sh
cat fixtures/extraction.json | ./TestExtractionPlugin | jq -e 'all(has("name") and has("suite"))'
```

### Running a plugin under a debugger

Editors launch a program directly rather than through a shell, so a run configuration cannot redirect a file into stdin. Read the envelope from an argument when one is given, and the problem disappears:

```ruby
payload = JSON.parse(ARGV[0] ? File.read(ARGV[0]) : $stdin.read)
```

```python
payload = json.load(open(sys.argv[1]) if len(sys.argv) > 1 else sys.stdin)
```

Mendoza always passes the envelope on stdin and never as an argument, so this costs nothing in production and keeps the payload out of `argv`, where it would be subject to the size limit that stdin exists to avoid. With that line in place, debugging is whatever your language already does — point your run configuration at the plugin and pass the fixture path as its argument:

```json
// .vscode/launch.json
{
  "type": "rdbg",
  "request": "launch",
  "script": "${workspaceFolder}/plugins/TearDownPlugin",
  "args": ["${workspaceFolder}/fixtures/teardown.json"]
}
```

Breakpoints, stepping and variable inspection then work as usual, with no pipes involved.

Saved envelopes also make plugins unit-testable: commit one as a fixture and assert your plugin's output in your own CI, with no Mendoza involved.

> **NOTE**
>
> The envelope contains your `--plugins_data` verbatim, so if that carries tokens or webhook URLs the dump does too. It is written `0600`, but **strip `data` before committing an envelope as a fixture**.

Anything your plugin writes to stderr is captured in the session logs at `/tmp/mendoza/logs/localhost-Plugin-<PluginName>.html`, even when the plugin succeeds. Note that `EventPlugin` failures are intentionally ignored so that a broken notification cannot fail a test run — for that plugin the HTML log is the only place its diagnostics appear.


# Configuration file and security

The `configure init` command will generate a configuration file containing all the information needed to compile, execute and distribute tests to a set of specified remote nodes. You can create different configuration files to test different test targets or use different remote nodes.

All the access credentials and passwords that are requested during initialization are stored locally in the current user’s Keychain. This means that you may be asked to update them by running `configure authentication` if something doesn’t match with what is specified in the configuration file (e.g. access credentials to a remote node).

# Node configuration

It is suggested that nodes are configured as follows:

## SSH MaxSessions

Set `MaxSessions` to 200 in /etc/ssh/sshd_config. You can check how many sessions are used by running `sudo lsof -nPiTCP:22 -sTCP:ESTABLISHED | grep mendoza | wc -l`

## SSH MaxStartups

Set `MaxStartups` to `200:30:300` in /etc/ssh/sshd_config (it is commented out by default, which leaves the low default of `10:30:100`). This is critical on the result destination node: during a run every test node opens a fresh SSH connection to it for each result transfer, and bursts of completing tests can briefly exceed the default unauthenticated-connection limit. When that happens sshd randomly drops connections, silently failing those transfers. Remember to restart sshd after changing the config.

## Increase maxfiles

`launchctl limit maxfiles 64000 524288`

## Increase max processes

`/usr/sbin/sysctl -w kern.maxprocperuid=4096 kern.maxproc=2500`

## Increase pseudo terminals

`/usr/sbin/sysctl -w kern.tty.ptmx_max=999`

# Building

By default Mendoza will build dynamically linking to libssh2 and libssl@3, which can be installed by running `brew install openssl@3 libssh2`. You can however create multi arch libraries that can be then linked statically by running the `./build_libs.rb` script and then using the `Shout-Static` package (which is commented in the Package.swift) instead of the default one.


# Contributions

Contributions are welcome! If you have a bug to report, feel free to help out by opening a new issue or sending a pull request.

# Authors

[Tomas Camin](https://github.com/tcamin) ([@tomascamin](https://twitter.com/tomascamin))


# License

Mendoza is available under the Apache License, Version 2.0. See the LICENSE file for more info.
