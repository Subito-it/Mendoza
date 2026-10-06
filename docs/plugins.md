# Plugins

Plugins customise steps of Mendoza's pipeline to fit your own workflow.

A plugin is **any executable file** — Ruby, Python, bash, a compiled binary, anything with a shebang. Mendoza writes a single JSON envelope to its **stdin** and reads the result from its **stdout**, so nodes need nothing installed beyond whatever your plugin itself requires.

| Plugin | Runs | Returns |
| --- | --- | --- |
| [`TestExtractionPlugin`](#testextractionplugin) | Instead of scanning the UI test target's files for test methods | The tests to run |
| [`TestSortingPlugin`](#testsortingplugin) | Before dispatch, to order the tests | The same tests, reordered |
| [`EventPlugin`](#eventplugin) | As the session progresses | Nothing |
| [`PreCompilationPlugin`](#precompilationplugin-and-postcompilationplugin) | Before compilation starts | Nothing |
| [`PostCompilationPlugin`](#precompilationplugin-and-postcompilationplugin) | After compilation ends, whether or not it succeeded | Nothing |
| [`TearDownPlugin`](#teardownplugin) | When the session ends, with its results | Nothing |

For where each plugin hooks into the pipeline, see [Under the hood](../md/under-the-hood.md).

## Contents

- [The contract](#the-contract)
- [Installing a plugin](#installing-a-plugin)
- [A complete plugin](#a-complete-plugin)
- [The plugins](#the-plugins)
- [Debugging plugins](#debugging-plugins)

## The contract

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
- `data` is the `--plugin_data` string, passed verbatim and never parsed by Mendoza. It is `null` when unset.

### `plugin describe`

Prints the JSON envelope a plugin receives on stdin and the output it is expected to write on stdout, together with a minimal starter script. The sample is generated from Mendoza's own types, so it always matches the version you are running.

```sh
mendoza plugin describe TearDownPlugin
```

## Installing a plugin

Three things must be true for a plugin to run:

1. the file is named **exactly** after the plugin type, with **no extension**, e.g. `TearDownPlugin`
2. it lives in the folder passed as `--plugins_path` (defaulting to the folder containing your configuration file)
3. it is executable — `chmod +x`. Mendoza will not set the bit for you

Get the first two wrong and the plugin is simply not found, which Mendoza treats differently depending on whether it needed a value from it:

- `TestExtractionPlugin` and `TestSortingPlugin` **fail the session**, since Mendoza cannot substitute a result for the one it asked for
- the other four are **skipped silently**, and the pipeline runs as if you had never installed one

A file that is found but not executable always fails the session, with the `chmod +x` to run. That asymmetry is deliberate: a misnamed file is indistinguishable from a plugin you chose not to install, while a missing executable bit is unambiguously a mistake.

## A complete plugin

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

> [!IMPORTANT]
> Never `print`/`puts` anything but the result: stdout **is** the result.

## The plugins

### TestExtractionPlugin

By default, test methods are extracted from every file in the UI testing target. That covers most projects, but not ones with custom rules about what runs where, for example tests tagged to run only on iPhone or only on iPad. This plugin replaces the default extraction with your own.

See the example [TestExtractionPlugin](../md/TestExtractionPlugin_example.rb).

### TestSortingPlugin

Without this plugin tests are dispatched in the order they were discovered, because Mendoza knows nothing about how long each one takes. Returning them from longest to shortest lets the slow tests start first, so the session doesn't end waiting on a single long test, and can cut total execution time significantly.

The plugin must return exactly the tests it was given: a result that adds or drops any fails the session rather than silently changing what runs. Tools like [Cachi](https://github.com/Subito-it/Cachi) can store and serve the test statistics to sort by.

See the example [TestSortingPlugin](../md/TestSortingPlugin_example.rb).

### EventPlugin

Invoked at each milestone of the session, with `kind` set to one of `start`, `startCompiling`, `stopCompiling`, `startTesting`, `stopTesting`, `stop` and `error`. Use it to send notifications or update a dashboard.

### PreCompilationPlugin and PostCompilationPlugin

Run on the compiling node around the build, for projects that need changes made before compilation, such as patching an Info.plist. The post compilation plugin runs whether or not compilation succeeded, so it is the place to undo whatever the pre compilation plugin changed.

### TearDownPlugin

Runs once the session ends and receives its results, so it can act on the outcome: publish a report, notify on failures, upload artifacts.

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

Anything your plugin writes to stderr is captured in the session logs at `/tmp/mendoza/logs/localhost-Plugin-<PluginName>.html`, even when the plugin succeeds. `EventPlugin` failures are intentionally ignored so that a broken notification cannot fail a test run — for that plugin the HTML log is the only place its diagnostics appear.

> [!CAUTION]
> The envelope contains your `--plugin_data` verbatim, so if that carries tokens or webhook URLs the dump does too. It is written `0600`, but **strip `data` before committing an envelope as a fixture**.

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
