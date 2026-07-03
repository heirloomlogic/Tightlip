# Changelog

All notable changes to Tightlip will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial open-source release.
- SwiftPM build-tool plugin (`Lipservice`) that reads `Secrets.yml` and generates a typed `Secrets` enum at build time.
- Flat and sectioned (multi-environment) `Secrets.yml` formats.
- Parse-time rejection of secret names that would produce a non-compiling generated file: Swift keywords, member names Swift rejects (`Type`, `Protocol`, `_`), the generated enum's `salt`/`decode` helpers and the symbols its decode shim references (`Data`, `String`, `UInt8`, `UTF8`, `fatalError`), and `envFile` (reserved for the directive).
- Environment selection via `TIGHTLIP_ENV` or inferred from `CONFIGURATION` (Xcode). Inference requires exactly one prod-named section and a stock `Debug`/`Release` configuration name; ambiguous cases — `prod` + `production` pairings, or a custom configuration name like `AppStore` — fail instead of guessing.
- `envFile:` directive for overriding the default `~/.zshenv` source. The declared path may not contain spaces, `#`, or be a bare identifier (ambiguous with a secret mapping); an explicitly declared file that doesn't exist is reported with a `note:`.
- The sourced env file is tracked as a build input alongside `Secrets.yml`, so editing either re-triggers generation without a clean build.
- All missing environment variables are reported in a single build — one `error:` line per variable, with the shell/CI guidance printed once — instead of one variable per fix-and-rebuild cycle.
- A `note:` when a declared env var resolves to the empty string (legal, but usually a leftover `export KEY=`).
- XOR-obfuscated literal output, deterministic across builds so identical inputs produce byte-identical generated files.
- Auto-sourcing of `~/.zshenv` in a clean zsh subshell, merged with `ProcessInfo` (build env wins on per-key conflicts). The capture never blocks the build: the timeout holds even against subshells that trap `SIGTERM` (escalating to `SIGKILL`) or leftover children holding the output pipe open. Capture failures are never silent: an `exit` inside the env file falls back to the process environment with a `note:`, a mid-file error reports the exit status and warns the captured environment may be partial, and a truncated capture drops the incomplete entry rather than baking a corrupted value.
- End-to-end test coverage that compiles and executes a generated `Secrets` enum, guarding against generation-validity regressions, plus a CI fixture package (`Fixtures/DemoApp`) that builds a real consumer with the plugin attached, asserts the generated value, and proves env-file edits re-trigger generation without a clean.
- DocC catalog with Diátaxis-shaped articles (tutorial, how-to guides, reference, explanation).
- GitHub Actions workflows for lint, test (newest and oldest supported Xcode), and documentation publishing.
- Top-level OSS documents: LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, THIRD_PARTY_NOTICES.
