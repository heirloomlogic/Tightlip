# Changelog

All notable changes to Tightlip will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
