# Contributing to Tightlip

Bug reports, fixes, and documentation improvements are all welcome.

## Reporting Bugs

Open a [bug report](https://github.com/heirloomlogic/Tightlip/issues/new?template=bug_report.md) with:

- The Swift and Xcode versions you are using
- Your `Secrets.yml` (with secret *values* redacted; key names and env-var names are fine to share)
- The environment variable names involved (no values)
- The full plugin output, including any `error:` or `note:` lines

## Submitting Changes

1. Fork the repository and create a branch from `main`.
2. Make your changes.
3. Run `touch .dev-tooling` once in your clone (enables linting — see [Code Style](#code-style)), then `swift build` and resolve any swift-format lint warnings.
4. Run `swift test` and confirm all tests pass.
5. Open a pull request describing what you changed and why.

### Code Style

The project uses [swift-format](https://github.com/swiftlang/swift-format) via a build plugin. The linter and DocC are dev-only dependencies gated behind a gitignored `.dev-tooling` sentinel file, so they never reach downstream consumers of the package. **Create the sentinel before your first build** so the first manifest evaluation picks it up:

```sh
touch .dev-tooling
```

Linting then runs automatically during builds, so `swift build` is enough to see all warnings. This works identically in Xcode, the command line, and Conductor — no environment variables or `launchctl` setup. Without the sentinel, `swift build` mirrors a consumer build and does not lint. Resolve all lint warnings before submitting a PR.

**Switching modes after a build.** SwiftPM caches the evaluated manifest keyed on `Package.swift`'s *text*, which is identical with or without the sentinel — so toggling `.dev-tooling` is invisible to the cache, and you'll keep getting whichever mode was evaluated first. The fix is to clear that one cache; a re-resolve then reconciles `Package.resolved` for you. Neither `swift package reset` nor Xcode's "Reset Package Caches" clears this layer.

- **Command line:** `swift package purge-cache`, then `swift package resolve`.
- **Xcode:** quit Xcode, run `swift package purge-cache`, then reopen `Package.swift`. If the old dependencies still appear, nudge a re-resolve with **File → Packages → Resolve Package Versions**. (Deleting DerivedData / `Package.resolved` works too but is rarely necessary.)

A fresh clone that creates the sentinel before its first build needs none of this. `Package.resolved` is gitignored, so this is all purely local — it never affects downstream consumers.

Your local toolchain must match CI's Swift major.minor version. If `swift build` surfaces lint errors that look unrelated to your changes, your toolchain is the likely culprit — update Xcode or install the matching Swift toolchain.

### Tests

New functionality should include tests. Bug fixes should include a test that would have caught the issue. The existing test suite under `Tests/TightlipCoreTests/` is the model: small, focused, one behavior per test.

### Documentation

If your change affects user-facing behavior, update the relevant DocC article under `Sources/TightlipCore/Documentation.docc/`. The README is intentionally short — most prose lives in DocC.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Questions

If you have questions that aren't covered here, open an issue or email tightlip@heirloomlogic.com.
