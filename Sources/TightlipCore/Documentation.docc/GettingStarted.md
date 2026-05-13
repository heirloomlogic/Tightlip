# Getting Started with Tightlip

Add the plugin to a target, drop in a `Secrets.yml`, and start reading secrets at compile time.

## Overview

Tightlip is a SwiftPM build-tool plugin. The plugin attaches to a target, reads a `Secrets.yml` config at the target's source root, resolves declared environment variables, and emits a Swift source file containing a `Secrets` enum compiled into your binary.

## Installation

### Swift Package Manager

Add the package as a dependency:

```swift
// Package.swift
.package(url: "https://github.com/heirloomlogic/Tightlip.git", from: "1.0.0"),
```

Attach the plugin to a target:

```swift
.target(
    name: "MyApp",
    plugins: [.plugin(name: "Lipservice", package: "Tightlip")]
)
```

Drop `Secrets.yml` at the target's source root, e.g. `Sources/MyApp/Secrets.yml`.

### Xcode project

1. **File → Add Package Dependencies...** → paste `https://github.com/heirloomlogic/Tightlip.git` → set Dependency Rule to **Up to Next Major** from `1.0.0`. (**Add Local...** also works for vendored checkouts.)
2. In the target's **Build Phases → Run Build Tool Plug-ins**, add **Lipservice**.
3. Create `<TargetName>/Secrets.yml` at the project root (the directory containing `.xcodeproj`). `<TargetName>` is the target's *display name*; the plugin resolves the path on the filesystem, not through Xcode's group tree, so the file's position in the Project Navigator is irrelevant. For a stock app template this is the `<TargetName>/` folder already at the top of the project.
4. Reference the generated enum anywhere in the target: `Secrets.revenueCatAPIKey`.

## Your First Secret

Create `Secrets.yml`:

```yaml
# Secrets.yml
revenueCatAPIKey: REVENUECAT_API_KEY
```

The left side is the Swift property name; the right side names an environment variable Tightlip resolves at build time. Export the variable before building:

```bash
export REVENUECAT_API_KEY="appl_…"
swift build
```

Reference the generated enum in your code:

```swift
let client = RevenueCat(apiKey: Secrets.revenueCatAPIKey)
```

If `REVENUECAT_API_KEY` is unset, the build fails with a clear error pointing at the missing variable. Every declared secret is required.

## What Just Happened

At build time Tightlip:

1. Parsed `Secrets.yml`.
2. Sourced `~/.zshenv` in a clean zsh subshell and merged the result with `ProcessInfo`.
3. Resolved each declared env var to its current value.
4. Emitted a Swift file containing a `Secrets` enum, with each value XOR-encoded against a salt derived from the values themselves.
5. The compiler included that file in your target.

The XOR encoding defends against `strings`-style extraction from the shipped binary; see <doc:Obfuscation> for the threat model.

## See Also

- <doc:SectionedConfigs>
- <doc:ConfigGrammar>
- <doc:EnvironmentSourcing>
