# Bazel projects

Mendoza can build an iOS `ios_ui_test` target with Bazel instead of `xcodebuild`. Run it from inside the Bazel workspace and pass the target instead of `--project` and `--scheme`:

```sh
mendoza test --bazel_target=//App:AppUITests --bazel_config=ci ...
```

Mendoza runs `bazel build` on the target and its `test_host`, then lays out the products as `xcodebuild build-for-testing` would: the app, a UI test runner built from the platform's `XCTRunner.app` and an `.xctestrun`. Distribution and test execution then proceed as for any other project.

## Configs

`--bazel_config` takes a comma separated list of configs, each passed as `--config`. Pass the configs your other builds use: Bazel only reuses cached outputs of builds with identical flags, and every flag change makes it discard its analysis cache. The test target, its test host and its sources are read with `bazel query` and `bazel cquery` using the same configs, so these queries reuse the build's analysis.

## Requirements and limitations

- The test target must have a `test_host` and exactly one `swift_library` dependency, whose sources Mendoza scans for tests.
- The products are downloaded even if a config uses `--remote_download_minimal`, since Mendoza copies them out of Bazel's output tree. Bundles built as archives (without `--define=apple.experimental.tree_artifact_outputs=1`) are extracted.
- The `env` and `args` attributes of the test target are not applied. Use `--device_language` and `--device_locale` to set up the simulators.
- `--build_configuration` and `--build_settings` only apply to `xcodebuild` and are rejected. `--clear_derived_data_on_failure` is ignored, as Bazel keeps its build state in its output base.

## Code coverage

Coverage is collected only if the configs instrument the app: `--collect_code_coverage`, `--experimental_use_llvm_covmap`, and an `--instrumentation_filter` matching the app's targets. Mendoza checks the built app and fails when it is not instrumented and `--individual_test_coverage` or `--test_covered_files` were passed, warning otherwise.

Bazel records source paths relative to the workspace, so coverage reports are the same whichever machine built the outputs.
