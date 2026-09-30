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
- When a value from the env file is `set but empty`, a `note:` before `result:` says it may read a build setting the check doesn't have. See <doc:CheckingConfig#Env-files-that-read-build-settings>.
- `result:` says whether a build would succeed.

When the section can't be determined, no variables are listed: the build stops before it resolves any.

## Exit status

The command exits non-zero when it finds that a build would fail at the Lipservice step for any checked target, and zero otherwise. A build can still disagree with it. Known cases: the environment can differ (see <doc:CheckingConfig#Check-the-environment-the-build-will-see>): `CONFIGURATION` is a stand-in, a native build passes the whole shell environment, and an Xcode.app build uses the environment Xcode was launched with. An env file can read a build setting, which fails the check and passes the build (see <doc:CheckingConfig#Env-files-that-read-build-settings>). A key file the env file reads can be deleted or emptied after the last build: the check reads the current file and fails, while an incremental build keeps the previous value because the plugin doesn't track that file (see the last paragraph of <doc:CheckingConfig#Env-files-that-read-build-settings>). A failure after the generated file is written, such as a compile error, is outside what it checks.

In a Swift package, SwiftPM runs the Lipservice build plugin while it prepares the command. The plugin's error for an env file copied into the bundle as a resource (see <doc:Troubleshooting>) therefore stops the command before any report prints, and it exits non-zero. Whether Xcode runs the build plugin before a command in a project has not been tested.

## Check the environment the build will see

The check starts from the environment of the shell that runs it and keeps the part that SwiftPM's default `swiftbuild` backend passes from the shell to the build tool: the variables `Secrets.yml` names in any section, `TIGHTLIP_ENV`, `HOME`, and `PATH`. It also keeps `CONFIGURATION`. A build sets that from `-c`, not from the shell; the check reads it from the shell as a stand-in, so set it to check a release build (below). The env file is sourced from that environment, as in a build, so a line like `export ACME_API_KEY="$CI_ACME_KEY"` reads an empty `CI_ACME_KEY` unless `Secrets.yml` names it. The deprecated native backend passes the whole shell environment, so a native build can find a value the check reports as empty or missing.

Xcode.app builds use the environment Xcode was launched with, which usually lacks exports made in a terminal. A variable that reports `from the build environment` in a terminal may be missing in an Xcode build. Put it in the env file instead. See <doc:EnvironmentSourcing>.

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

### Env files that read build settings

A `swiftbuild` build also passes the build tool its build settings, several hundred of them, including `SRCROOT` and `PROJECT_DIR`. The check runs outside a build and has none of them, even when the shell exports one. So an env file line such as

```bash
export ACME_API_KEY="$(cat "$SRCROOT/secrets/acme-key")"
```

resolves in a `swiftbuild` build but comes out empty in the check. The check reports the variable as `set but empty`, prints a note about build settings, and exits non-zero, although the build would succeed. The check can't tell a build setting from a variable a build would also leave unset, so it fails on both.

A native SwiftPM build doesn't set `SRCROOT`, so the same line fails there unless the shell exports it. To read a file stored beside the env file, use the env file's own directory, which zsh provides as `${0:a:h}`:

```bash
export ACME_API_KEY="$(cat "${0:a:h}/secrets/acme-key")"
```

That resolves in the check and in SwiftPM builds with either backend. The plugin tracks the env file as a build input, not the files it reads, so editing `secrets/acme-key` alone leaves the previous value in the built product until something else, such as an edit to the env file, regenerates it. If an env file has to read a build setting, the check can't verify that target; name the other targets with `--target` to check them.

## Xcode projects

`swift package` needs a `Package.swift`, so an Xcode project runs the command from Xcode instead: right-click the project in the Project navigator and choose it from the package plugin commands listed there. For each target, it checks `<TargetName>/Secrets.yml` beside the `.xcodeproj`, the same path the build plugin reads.

Running the command inside an Xcode project has not been tested. The check most likely sees the environment Xcode was launched with and no build settings. If so, a `TIGHTLIP_ENV` set as a user-defined build setting, or the `CONFIGURATION` a build gets from its scheme, is unset during the check, and an env file that reads a build setting fails the check as described in <doc:CheckingConfig#Env-files-that-read-build-settings>.

## See Also

- <doc:EnvironmentSelection>
- <doc:Troubleshooting>
- <doc:ContinuousIntegration>
