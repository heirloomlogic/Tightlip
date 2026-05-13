# Contributing to Tightlip

Tightlip is the SwiftPM build-tool plugin that powers secret management in [Heirloom Logic](https://heirloomlogic.com)'s apps. Contributions that improve the plugin benefit everyone building with it.

## Reporting Bugs

Open a [bug report](https://github.com/heirloomlogic/Tightlip/issues/new?template=bug_report.md) with:

- The Swift and Xcode versions you are using
- Your `Secrets.yml` (with secret *values* redacted; key names and env-var names are fine to share)
- The environment variable names involved (no values)
- The full plugin output, including any `error:` or `note:` lines

## Submitting Changes

1. Fork the repository and create a branch from `main`.
2. Make your changes.
3. Run `swift build` and resolve any swift-format lint warnings.
4. Run `swift test` and confirm all tests pass.
5. Open a pull request describing what you changed and why.

### Code Style

The project uses [swift-format](https://github.com/swiftlang/swift-format) via a build plugin. Linting runs automatically during builds, so `swift build` is enough to see all warnings. Resolve all lint warnings before submitting a PR.

Your local toolchain must match CI's Swift major.minor version. If `swift build` surfaces lint errors that look unrelated to your changes, your toolchain is the likely culprit — update Xcode or install the matching Swift toolchain.

### Tests

New functionality should include tests. Bug fixes should include a test that would have caught the issue. The existing test suite under `Tests/TightlipCoreTests/` is the model: small, focused, one behavior per test.

### Documentation

If your change affects user-facing behavior, update the relevant DocC article under `Sources/TightlipCore/Documentation.docc/`. The README is intentionally short — most prose lives in DocC.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Questions

If you have questions that aren't covered here, open an issue or email tightlip@heirloomlogic.com.
