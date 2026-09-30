# Checking a Config Without Building

See which section a build would select and which variables it would find, without compiling anything.

## Overview

The `tightlip-check` command runs the build tool's steps up to the point where it would write the generated file: it parses `Secrets.yml`, sources the env file, selects the section, and resolves every declared variable. Then it prints a report. It never prints a value and never writes a file.

```bash
swift package tightlip-check
swift package tightlip-check --target MyApp
```

With no `--target`, it checks every target in the package that has a `Secrets.yml` at its source root. `--target` can be repeated. A named target that has no `Secrets.yml` fails with the same "config missing" error a build gives.

The command comes from the `TightlipCheck` plugin product. Adding Tightlip as a dependency is enough; you don't attach the plugin to a target.

## Read the report

```
Checking MyApp (/path/to/Sources/MyApp/Secrets.yml)
note: using environment 'staging'
note: 1 env var(s) with prefix 'ACME_' visible to the build: [ACME_API_KEY]; total env count = 84
error: environment variable ACME_ANALYTICS_ID must be set to generate Secrets.analyticsID
note: set the missing variable(s) in your shell, ~/.zshenv (for Xcode.app), or your CI environment
environment: staging (CONFIGURATION is unset, which infers the same section as Debug; Debug selects 'staging', Release selects 'production')
env file: /Users/you/.zshenv
variables:
  ACME_API_KEY (Secrets.apiKey): set, from the env file
  ACME_ANALYTICS_ID (Secrets.analyticsID): missing
  ACME_FEATURE_FLAGS (Secrets.featureFlags): set but empty (allowed), from the build environment
result: a build would fail
```

The lines before `environment:` are the diagnostics a build would print, in the same form. Parse errors keep the `path:line: error:` shape. The report follows:

- `environment:` is the selected section and the rule that chose it: `TIGHTLIP_ENV`, inference from `CONFIGURATION`, or `cannot determine` with the reason. Flat configs say `none (flat config)`. Outside a build `CONFIGURATION` is usually unset, and the report says so. When inference applies, it also names the sections `Debug` and `Release` select. See <doc:EnvironmentSelection>.
- `env file:` is the file the check sourced, marked `(not found)` when it doesn't exist.
- `variables:` lists every variable the selected section declares, with the property it generates. The state is one of:
  - `set`: a non-empty value.
  - `set but empty (allowed)`: the empty string, which the variable's `?` marker allows.
  - `set but empty`: the empty string with no `?` marker. A build fails.
  - `missing`: set in neither the env file nor the environment. A build fails.

  The source is `from the env file` or `from the build environment`. When both have a value, the environment wins, as it does in a build.
- `result:` says whether a build would succeed.

When the section can't be determined, no variables are listed: the build stops before it resolves any.

## Exit status

The command exits non-zero when a build would fail at the Lipservice step for any checked target, and zero otherwise. Two build failures are outside what it checks: the build plugin's error for an env file copied into the bundle as a resource (see <doc:Troubleshooting>), and anything after the generated file is written, such as a compile error.

## Check the environment the build will see

The check reads the environment of the shell that runs it, the same one `swift build` in that shell would use. Xcode.app builds use the environment Xcode was launched with, which usually lacks exports made in a terminal. A variable that reports `from the build environment` in a terminal may be missing in an Xcode build. Put it in the env file instead. See <doc:EnvironmentSourcing>.

To check a release lane, set what the lane sets:

```bash
CONFIGURATION=Release swift package tightlip-check
TIGHTLIP_ENV=production swift package tightlip-check
```

In CI, run it as a step before the build. It fails in seconds, and its report names every variable the job is missing:

```yaml
- name: Check secrets
  env:
    TIGHTLIP_ENV: production
    ACME_API_KEY: ${{ secrets.ACME_API_KEY }}
  run: swift package tightlip-check --target MyApp
```

## Xcode projects

`swift package` needs a `Package.swift`, so an Xcode project runs the command from Xcode instead: right-click the project in the Project navigator and choose it from the package plugin commands listed there. For each target, it checks `<TargetName>/Secrets.yml` beside the `.xcodeproj`, the same path the build plugin reads.

In Xcode the check sees the environment Xcode was launched with, but not build settings. A `TIGHTLIP_ENV` set as a user-defined build setting, or the `CONFIGURATION` a build gets from its scheme, is unset during the check.

## See Also

- <doc:EnvironmentSelection>
- <doc:Troubleshooting>
- <doc:ContinuousIntegration>
