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
|   🔌   | Supports plugins (written in Swift!) |
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

## `plugin init`

This command allows to create a plugin template script that will be used during the execution of the tests. Refer to the [plugins](#Plugins) paragraph.

## `test`

Will launch tests as specified in the configuration files.


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

A plugin is initialized with the `plugin init` command. The plugin file that is generated contains a struct with a single `handle()` method with a signature that depends on the plugin. The types in the signature are showed as comments above the struct definition.

The following plugins are available:

- `extract`: allows to specify the test methods that should be performed in every test file
- `sorting`: plugin to add estimated execution time to test cases
- `event`: plugin to perform actions (e.g. notifications) based on dispatching events
- `precompilation`: plugin to perform actions before compilation starts
- `postcompilation`: plugin to perform actions after compilation completes
- `teardown`: plugin to perform actions at the end of the dispatch process

You should definitely consider using [swift sh](https://github.com/mxcl/swift-sh) if your plugins requires additional dependencies.


## extract

By default test methods will be extracted from all files in the UI testing target. This should work most of the times however in some advanced cases this could not be the desired behaviour, for example if there is some custom tagging to run tests on specific devices (e.g. only iPhone/iPad). This plugin allows to override the default behaviour and put in place a custom implementation

See an example [TestExtractionPlugin.swift](md/TestExtractionPlugin_example.swift).


## sorting

By default test cases will be executed randomly because Mendoza has no information about the execution time of test cases. Mendoza can significantly improve total execution time of test if you provide an estimate of the execution time of tests.

Using tools like [Cachi](https://github.com/Subito-it/Cachi) you can automatically store and retrieve tests statistics.

See an example [TestSortingPlugin.swift](md/TestSortingPlugin_example.swift).


## event

This plugin will be invoked during the different steps of Mendoza's pipeline. You'll be notified when compilation starts/ends, when tests bundles start/end being distributed and so on. Based on these event you could for example send notifications.


## precompilation

Your project might be so heavily customized that you might need to perform some changes to the project before the compilation of the UI testing target begins.


## postcompilation

If you're using a precompilation plugin you might also need a post compilation plugin to restore any change previously made.


## teardown

This plugin allows to perform custom actions once the test session ends. You'll get some result information as input in order to perform action accoring to the test session outcome



## Debugging plugins

The files used by Mendoza internally to execute plugins won't be deleted when you run tests passing the `--plugin_debug` flag. After a test session, in the same folder of your plugins, you'll find 2 additional files: one with the same filename of the plugin but prefixed with an underscore and a file with a _.debug_ extension. The _.debug_ file will invoke the plugin file and pass arguments to it.

An easy way to debug a plugins is to create a new macOS command line tool project in Xcode, copy paste the content of the __Pluginfile.swft_ and add the arguments to the scheme settings. From there you can use Xcode to run an debug the plugin.


# Configuration file and security

The `configure init` command will generate a configuration file containing all the information needed to compile, execute and distribute tests to a set of specified remote nodes. You can create different configuration files to test different test targets or use different remote nodes.

All the access credentials and passwords that are requested during initialization are stored locally in the current user’s Keychain. This means that you may be asked to update them by running `configure authentication` if something doesn’t match with what is specified in the configuration file (e.g. access credentials to a remote node).

# Node configuration

It is suggested that nodes are configured as follows:

## SSH MaxSessions

Set `MaxSessions` to 200 in /etc/ssh/sshd_config. You can check how many sessions are used by running `sudo lsof -nPiTCP:22 -sTCP:ESTABLISHED | grep mendoza | wc -l`

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
