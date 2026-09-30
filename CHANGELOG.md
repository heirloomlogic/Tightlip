# Changelog

All notable changes to Tightlip will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Parse-time rejection of secret names that would produce a non-compiling generated file: Swift keywords, member names Swift rejects (`Type`, `Protocol`, `_`), the generated enum's `salt`/`decode` helpers, and `envFile` (reserved for the directive).
- End-to-end test coverage that compiles and executes a generated `Secrets` enum, guarding against generation-validity regressions, plus a CI fixture package (`Fixtures/DemoApp`) that builds a real consumer with the plugin attached, asserts the generated value, proves env-file edits re-trigger generation without a clean, and proves build-environment values reach the tool and a `TIGHTLIP_ENV` flip regenerates.
- An oldest-supported-toolchain CI job (Xcode 16.3, pinned to `macos-15`).
- Parse error naming invisible characters (no-break space, zero-width space, stray CR) with column.
- A `?` after an env-var name in `Secrets.yml` (`analyticsKey: ANALYTICS_KEY?`) allows that variable to be empty. It applies per line, so sections can differ. An unset variable is still an error.
- An `access:` directive (`internal`, the default; `package`; or `public`) sets the access level of the generated `Secrets` enum and every property on it, for apps that keep secrets in one module and read them from others. `package` and `public` widen the secrets module's API surface to every target that can see it; the directive is for module boundaries inside one app, not for shipping a library. `package` needs the secrets target and its readers in the same SwiftPM package. `internal` output is byte-identical to a config without the directive. `envFile:` and `access:` may appear in either order before the first section or mapping, and the plugin still tracks the env file as a build input with `access:` first. `ParsedConfigFile` gains `access`, and `renderSecretsEnum` takes an `access:` argument.
- A `tightlip-check` command (`swift package tightlip-check [--target <name>]`, from the new `TightlipCheck` plugin product) runs the build tool's parse, environment, and resolution steps without writing anything. It prints the diagnostics a build would, the selected section and the rule that chose it (`TIGHTLIP_ENV`, `CONFIGURATION` inference, or `cannot determine`), and each declared variable as `set`, `set but empty (allowed)`, `set but empty`, or `missing`, with whether the value came from the env file or the build environment. It never prints values, and it exits non-zero when the Lipservice step of a build in the same environment would fail. It sources the env file from the variables a `swiftbuild` build passes to the tool, not the whole shell environment. Xcode projects can run it from the Project navigator (untested in Xcode). `selectEnvironment`, `evaluateSecretsConfig`, and `checkSecretsConfig` join TightlipCore's API, with the `SectionSelection`, `VariableStatus`, and `SecretsEvaluation` types they return; `generateSecretsFile` is now `evaluateSecretsConfig` plus rendering, with unchanged output.

### Changed
- Environment inference now requires exactly one prod-named section and a stock `Debug`/`Release` configuration name; ambiguous cases — `prod` + `production` pairings, or a custom configuration name like `AppStore` — fail instead of guessing. **Breaking:** builds that relied on the previous guessing behavior with a custom configuration name must now set `TIGHTLIP_ENV` explicitly.
- `envFile:` paths may not contain spaces, `#`, quotes, `$`, or backticks, may not be a bare identifier (ambiguous with a secret mapping), a `~user/…` path, `~` alone, or end in `/`; an explicitly declared file that doesn't exist, is a directory, or is unreadable falls back with a `note:`. **Breaking:** `envFile: ~`, previously accepted, pointed at the home directory and sourced nothing.
- All missing environment variables are reported in a single build — one `error:` line per variable, with the shell/CI guidance printed once — instead of one variable per fix-and-rebuild cycle.
- Parse errors print as `path:line: error: reason` so Xcode attributes them to the line; section-level errors carry the header's line number.
- The generated shim spells library symbols module-qualified, so consumer types named `Data`/`UTF8` no longer break it; `Data`, `String`, `UInt8`, `UTF8`, `fatalError`, `open` are allowed as secret names; `Swift` and `Foundation` are now reserved.
- **Breaking:** a declared env var set to the empty string fails the build with `error: environment variable X is set but empty; …` (previously an empty value built silently with no warning). Empty and missing variables are reported together in one build, one `error:` per variable, with shared guidance printed once. Mark variables that may legitimately be empty with `?`. `ParsedSecret` gains `allowsEmpty`, `resolveSecret` throws the new `ConfigError.emptyEnvironmentVariable`, and `envFile: NAME?` is rejected as ambiguous, like `envFile: NAME`.
- **Breaking:** `access` is reserved as a secret name, like `envFile`. A config that declares a secret named `access` fails to parse; rename it.
- A new `warning:` when the build environment overrides a different, non-empty value the env file exports for a declared variable (a `note:` for `TIGHTLIP_ENV`).
- The generated file is not rewritten when unchanged (Xcode projects re-run build-tool commands every build; this avoids recompiling it).
- ~19x faster decode in unoptimized builds.

### Fixed
- The sourced env file is tracked as a build input alongside `Secrets.yml`, so editing either re-triggers generation without a clean build.
- The environment capture never blocks the build: the timeout holds even against subshells that trap `SIGTERM` (escalating to `SIGKILL`) or leftover children holding the output pipe open; an `exit` inside the env file falls back to the process environment with a `note:`, a mid-file error reports the exit status and warns the captured environment may be partial, and a truncated capture drops the incomplete entry rather than baking a corrupted value.
- Under SwiftPM's default `swiftbuild` backend, build-environment variables (CI `env:`, `TIGHTLIP_ENV`) never reached the tool; the plugin now forwards the variables `Secrets.yml` names plus `TIGHTLIP_ENV` through a 0600 file in its work directory, declared as a build input.
- Changing `TIGHTLIP_ENV` or a declared variable's value in the build environment now regenerates without a clean (previously a `TIGHTLIP_ENV` flip on reused DerivedData silently kept the other environment's keys).
- A missing `Secrets.yml` in package builds showed an opaque "Build input file cannot be found" error; the tool's own message now appears.
- Env capture: stdin is `/dev/null`; traps, zshexit hooks, background jobs, and functions in the env file can't alter the dump; `setopt err_exit` no longer discards exports; an environment too large for `/usr/bin/env` falls back with a note instead of silently dropping every sourced variable; timeouts kill the whole process group; non-UTF-8 values are dropped with a note instead of decoded lossily.
- The missing-variable typo-hunting note keeps a leading underscore in the prefix.

### Security
- The plugin fails the build when the env file is a bundle resource (or inside a directory resource), and warns when `Secrets.yml` is. Xcode's synchronized folders (the default for new targets) copy every non-source file in a target's folder into the built app, so a project-local env file shipped its plaintext values inside the bundle.

## [1.2.1] - 2026-06-06

### Changed
- Documented CI pain points from the first downstream integration: use `-destination` instead of `-sdk` so the plugin's host tool builds for macOS, supply environment variables on every lane that compiles the target, and capture raw logs past `xcbeautify`; added a Troubleshooting how-to guide.
- Documented the project-local env-file recipe enabled by the existing `envFile:` directive, and the rationale for not adding a dedicated `.env` feature.

## [1.2.0] - 2026-06-04

### Fixed
- The `Lipservice` plugin tool failed to compile for non-macOS targets (e.g. the iOS Simulator), because Xcode builds a build-tool plugin's executable for the consuming app's target platform rather than the macOS host it runs on; `Process`-based shell sourcing is now guarded under `#if os(macOS)` and the package declares the platforms (iOS 13 / tvOS 13 / watchOS 6 / macOS 10.15) the README already advertised.

## [1.1.0] - 2026-06-04

### Changed
- Gated dev-only tooling (the `Persnoop` swift-format plugin and its dependencies) behind a gitignored `.dev-tooling` sentinel, so consumers resolve a clean dependency graph instead of inheriting a dev-only linter.

## [1.0.0] - 2026-06-03

### Added
- Recommended the `tightlip-ref` agent skill in README and DocC, with install/update commands for Claude Code and Codex.

### Changed
- Tightened README, CONTRIBUTING, and DocC prose.
- Reordered the README header above the shield badges and dropped the `.git` suffix from package URLs.

## [0.1.0] - 2026-05-13

### Added
- Initial open-source release.
- SwiftPM build-tool plugin (`Lipservice`) that reads `Secrets.yml` and generates a typed `Secrets` enum at build time.
- Flat and sectioned (multi-environment) `Secrets.yml` formats.
- Environment selection via `TIGHTLIP_ENV` or inferred from `CONFIGURATION` (Xcode).
- `envFile:` directive for overriding the default `~/.zshenv` source.
- XOR-obfuscated literal output, deterministic across builds so identical inputs produce byte-identical generated files.
- Auto-sourcing of `~/.zshenv` in a clean zsh subshell, merged with `ProcessInfo` (build env wins on per-key conflicts).
- DocC catalog with Diátaxis-shaped articles (tutorial, how-to guides, reference, explanation).
- GitHub Actions workflows for lint, test, and documentation publishing.
- Top-level OSS documents: LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, THIRD_PARTY_NOTICES.

[Unreleased]: https://github.com/heirloomlogic/Tightlip/compare/1.2.1...HEAD
[1.2.1]: https://github.com/heirloomlogic/Tightlip/compare/1.2.0...1.2.1
[1.2.0]: https://github.com/heirloomlogic/Tightlip/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/heirloomlogic/Tightlip/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/heirloomlogic/Tightlip/compare/0.1.0...1.0.0
[0.1.0]: https://github.com/heirloomlogic/Tightlip/releases/tag/0.1.0
