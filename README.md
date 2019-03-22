# 🍷 Mendoza 

Mendoza allows to parallelize Apple's UI Tests over multiple physical machines. While Xcode recently introduced parallelization it is limited to a single local machine requiring top-notch hardware to run tests on several simulators at once. 

Mendoza is designed to parallelize tests on an unlimited number of different machines offering a scalable solution to reduce UI Testing's execution times. There are no particular contraints on the hardware that can be used, as an example we use rather oldish 2013 i5 MacBooks.

The tool is flexible thanks to [plugins](#Plugins) (that you can write in Swift 😎) allowing to heavily customize several steps in the dispatching pipeline.

The outcome of a test session will be a set of log files (.json, .html) that will merge result together as if all tests were run on a single machine.

A snapshot of a session running on 8 concurrent nodes (each running 2 simulators at once) can be seen below.

<img src='md/running.png' width='724'>


| | Features |
:---: | --- |
🏃‍♀️ | Makes UI Test execution super fast! |
👨🏻‍💻 | Written in Swift  |
🔌 | Supports plugins (written in Swift!) |
🔍 | Wide set of result formats |


# How does it work

The basic idea is simple: you compile a project on one machine, distribute the compiled package (test bundle) to a number of specified remote nodes, execute a subset of tests on each node and collect the results back together as if they were run on a single machine. Depending on the node hardware configuration you can also run multiple simulators at once.

Mendoza hides all the complexity behind a single `test` command by leveraging built in command line tools to perform each of the aforementioned steps. To get an idea of what’s under the hood take a look [here](md/under-the-hood.md).



# Installation

```
brew install Subito-it/made/mendoza
```

Or you can build manually using swift build.

Mendoza in written in Swift 5, so if you're on macOS Mojave 10.14.3 or earlier, you may need to install an optional Swift library package that can be downloaded from "More Downloads" for Apple Developers at https://developer.apple.com/download/more/


# Quick start

Inside your project folder run

```
mendoza configure init
```

this will prompt you with a series of (fairly self-explanatory) questions and produce a configuration file that you will feed to the `test` command as follows:

```
mendoza test configuration.json --device_name="iPhone 8" --device_runtime="12.1"
```

This will compile your project, distribute the test bundles, execute the tests, collect the results together on the _destination_ node that was specified during setup and generate a set of [output files](#test-output).



# Commands

## `configuration init`

Generates a new configuration file required to execute tests. you will be prompted with a series of (fairly self-explanatory) questions which will produce a json configuration file as an output.

### Concepts

#### AppleID

During initialization you will be prompted for an Apple ID account that will be used to install new runtimes on testing nodes. Any low priviledge Apple ID account will work.

When not provided test dispatch will fail if the requested simulator runtime isn't properly installed.

#### Nodes configuration

When setting up nodes you'll be asked to specify a label that identifies the node, the address, an authentication method and the administrator password that will be required to install new runtimes if needed. When not providing the administrator password test dispatch will fail if the requested simulator runtime isn't properly installed.

You'll be asked how many simulators to run at once, the rule of thumb is that you can run 1 simulator per physical CPU core. Specifying more that one simulator per core will work but this will result in slower total execution time because the node will be over-utilized.

Optionally you can specify if the node should use a ram disk. This has a significant benefit in performances on older machines that have no SSD disk.

#### Destination node

The destination node is the node that will be responsible to collect all the result logs.

## configuration authentication

The credentials and passwords you will be asked during initialization are stored locally in your Keychain (see [configuration file and security](#Configuration-file-and-security) paragraph). This means that if the configuration was generated on a different machine you may be missing those credentials/passwords. The `configuration authentication` command will prompt and store missing credentials/password in your local Keychain.

## `plugin init`

This command allows to create a plugin template script that will be used during the execution of the tests. Refer to the [plugins](#Plugins) paragraph.

## `test`

Will launch tests as specified in the configuration files.

#### Required parameters
- path to the configuration file
- --device_name=name: device name to use to run tests. e.g. 'iPhone 8'
- --device_runtime=version: device runtime to use to run tests. e.g. '12.1'

#### Optional parameters

- --timeout=[minutes]: maximum allowed time (in minutes) before dispatch process is automatically terminated
- --include_files=[files]: specify from which files UI tests should be extracted. Accepts wildcards and comma separated. e.g SBTA*.swift,SBTF*.swift. (default: '*.swift')
- --exclude_files=[files]: specify which files should be skipped when extracting UI tests. Accepts wildcards and comma separated. e.g SBTA*.swift,SBTF*.swift. (default: '')
- --plugin_data=[data]: a custom string that can be used to inject data to plugins
- --plugin_debug: write log files for plugin development. Refer to the [plugins](#Plugins) paragraph. 
- --use_localhost: 🔥 when passing these flag tests will be dispatched on the localhost as well even if it is not specified in the configuration file. This is useful when launching tests locally leveraging additional simulators of your own development machine.

### Test output

Mendoza will write a set of log files containing information about the test session:

- test_details.json: provides a detailed insight of the test session
- test_result.json: the list of tests that passed/failed in json format
- test_result.html: the list of tests that passed/failed in html format

If you're interested in seeing the specific actions that made a test fail you may either manually inspect the TestSummaries.plist file associated with the failing test (see _test_details.json_) or more conveniently use [sbtuitestbrowser](https://github.com/Subito-it/sbtuitestbrowser) which is able to parse and present results as you normally do in Xcode directly in a web browser.




# Plugins

Plugins allow to customize various steps of Mendoza's pipeline. This opens up to several optimizations that are stricly related to your own specific workflows. 

A plugin is initialized with the `plugin init` command. The plugin file that is generated contains a struct with a single `handle()` method with a signature that depends on the plugin. The types in the signature are showed as comments above the struct definition.

The following plugins are available:

- `extract`: allows to specify the test methods that should be performed in every test file
- `distribute`: allows to specify which node should run every test method
- `event`: plugin to perform actions (e.g. notifications) based on dispatching events
- `precompilation`: plugin to perform actions before compilation starts
- `postcompilation`: plugin to perform actions after compilation completes
- `teardown`: plugin to perform actions at the end of the dispatch process

You should definitely consider using [swift sh](https://github.com/mxcl/swift-sh) if your plugins requires additional dependencies.


## extract

By default test methods will be extracted from all files in the UI testing target. This should work most of the times however in some advanced cases this could not be the desired behaviour, for example if there is some custom tagging to run tests on specific devices (e.g. only iPhone/iPad). This plugin allows to override the default behaviour and put in place a custom implementation


## distribute

By default test cases will be evenly distributed over the available nodes because Mendoza it has no information about the execution time of each test case. For example if you have 100 test cases and 5 nodes, each node will execute 20 tests. Depending on the variance of execution time of the test cases you might end up with one node taking significant more time than other to complete all tests.

On the other hand if, for example, you're using [sbtuitestbrowser](https://github.com/Subito-it/sbtuitestbrowser) you might leverage it's [test case statistics](https://github.com/Subito-it/sbtuitestbrowser#test-case-stats) feature allowing you to override the default behaviour and equally distribute the total execution time per node of your test session.

See the example [TestDistributionPlugin.swift](md/TestDistributionPlugin_example.swift).


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



# Contributions

Contributions are welcome! If you have a bug to report, feel free to help out by opening a new issue or sending a pull request.



# Authors

[Tomas Camin](https://github.com/tcamin) ([@tomascamin](https://twitter.com/tomascamin))



# License

Mendoza is available under the Apache License, Version 2.0. See the LICENSE file for more info.
