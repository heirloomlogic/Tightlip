# Getting Started with Tightlip

Add the plugin to a target, drop in a `Secrets.yml`, and start reading secrets at compile time.

## Overview

Tightlip is a SwiftPM build-tool plugin. The plugin attaches to a target, reads a `Secrets.yml` config at the target's source root, resolves declared environment variables, and emits a Swift source file containing a `Secrets` enum compiled into your binary.

## Installation

### Swift Package Manager

Add the package as a dependency:

```swift
// Package.swift
.package(url: "https://github.com/heirloomlogic/Tightlip", from: "1.0.0"),
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

1. **File → Add Package Dependencies...** → paste `https://github.com/heirloomlogic/Tightlip` → set Dependency Rule to **Up to Next Major** from `1.0.0`. (**Add Local...** also works for vendored checkouts.)
2. In the target's **Build Phases → Run Build Tool Plug-ins**, add **Lipservice**. The package dependency dialog lists both `Lipservice` and a `LipserviceTool` executable — attach **only** `Lipservice` here, and do **not** add `LipserviceTool` to the target's *Frameworks, Libraries, and Embedded Content*. `LipserviceTool` is the host tool the plugin runs for you; linking it into an app target builds it for the wrong platform and accomplishes nothing.
3. Create `<TargetName>/Secrets.yml` at the project root (the directory containing `.xcodeproj`). `<TargetName>` is the target's *display name*; the plugin resolves the path on the filesystem, not through Xcode's group tree, so the file's position in the Project Navigator is irrelevant. For a stock app template this is the `<TargetName>/` folder already at the top of the project. That folder is synchronized, so Xcode adds the new file to the target and would copy it into the app bundle: select `Secrets.yml`, open the File inspector, and clear its **Target Membership** checkbox. The plugin reads the file from disk and warns while it's still a member.
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

If `REVENUECAT_API_KEY` is unset or empty, the build fails with an error naming the variable. Every declared secret is required.

## Using the Generated API

The generated `nonisolated enum Secrets` lives in the consuming target's module. Read its `String` properties directly: no `import Tightlip`, initialization, or actor hop is needed. Keep the generated `Tightlip.swift` in the build directory; commit `Secrets.yml`, which contains variable names, rather than generated code or secret values. For access from another module, see <doc:SharingAcrossModules>.

## Adding, Renaming, and Rotating Secrets

- **Add:** export the new variable in your env file or build environment, add its property mapping to `Secrets.yml`, build, and use `Secrets.propertyName`. With sectioned configs, add the property to every section; only the selected section's variables need values for that build. See <doc:ConfigGrammar> and <doc:SectionedConfigs>.
- **Rename:** update the property in every section and all Swift call sites. If renaming the environment variable instead, update the mapping and the corresponding local and CI exports.
- **Rotate:** update the variable's value and rebuild each affected app/environment. Tightlip embeds values at build time; deployed apps need a new build to receive the change. Direct edits to the configured env file or declared build-environment variables trigger regeneration; files read indirectly by the env file are not tracked. See <doc:EnvironmentSourcing> and <doc:CheckingConfig>.
- **Remove:** delete the property from every section and remove its call sites; remove unused exports from local and CI configuration.

When replacing a hardcoded value, also check tracked fixtures, snapshots, and generated artifacts for copies without printing the value into logs. Removing a literal from current source does not remove it from Git history; treat an exposed credential as compromised and rotate it.

Validate the selected environment with <doc:CheckingConfig>, then build the consuming target. A successful config check verifies secret resolution, not compilation. Use <doc:ContinuousIntegration> for every CI lane that compiles the target and <doc:Troubleshooting> for failures.

## What Just Happened

At build time Tightlip:

1. Parsed `Secrets.yml`.
2. Sourced `~/.zshenv` in a clean zsh subshell and merged the result with the build environment.
3. Resolved each declared env var to its current value.
4. Emitted a Swift file containing a `Secrets` enum, with each value XOR-encoded against a salt derived from the values themselves.
5. The compiler included that file in your target.

The XOR encoding defends against `strings`-style extraction from the shipped binary; see <doc:Obfuscation> for the threat model.

## See Also

- <doc:SectionedConfigs>
- <doc:ConfigGrammar>
- <doc:EnvironmentSourcing>
- <doc:ContinuousIntegration>
- <doc:Troubleshooting>
