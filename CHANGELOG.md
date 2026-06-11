# Changelog

All notable changes to Tightlip will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial open-source release.
- SwiftPM build-tool plugin (`Lipservice`) that reads `Secrets.yml` and generates a typed `Secrets` enum at build time.
- Flat and sectioned (multi-environment) `Secrets.yml` formats.
- Parse-time rejection of secret names that are Swift keywords or collide with the generated enum's `salt`/`decode` helpers, which would otherwise produce a non-compiling generated file.
- Environment selection via `TIGHTLIP_ENV` or inferred from `CONFIGURATION` (Xcode). Inference requires exactly one prod-named section; ambiguous `prod` + `production` pairings fail instead of guessing.
- `envFile:` directive for overriding the default `~/.zshenv` source.
- XOR-obfuscated literal output, deterministic across builds so identical inputs produce byte-identical generated files.
- Auto-sourcing of `~/.zshenv` in a clean zsh subshell, merged with `ProcessInfo` (build env wins on per-key conflicts). The capture never blocks the build: the timeout holds even against subshells that trap `SIGTERM` (escalating to `SIGKILL`) or leftover children holding the output pipe open.
- End-to-end test coverage that compiles and executes a generated `Secrets` enum, guarding against generation-validity regressions.
- DocC catalog with Diátaxis-shaped articles (tutorial, how-to guides, reference, explanation).
- GitHub Actions workflows for lint, test, and documentation publishing.
- Top-level OSS documents: LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, THIRD_PARTY_NOTICES.
