<p align="center">
  <img src=".github/Tightlip-logo@2x.png" alt="Tightlip" width="256">
</p>

[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue.svg)](https://heirloomlogic.github.io/Tightlip/documentation/tightlipcore/)

# Tightlip

A SwiftPM build-tool plugin that generates a typed Swift `Secrets` enum from environment variables at build time. The generated file lives in the plugin's work directory and is compiled into the consuming target. Secrets never enter source control.

## Installation

### Swift Package Manager

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

Drop `Secrets.yml` at the target's source root (e.g. `Sources/MyApp/Secrets.yml`).

### Xcode project

1. `File > Add Package Dependencies...` → paste `https://github.com/heirloomlogic/Tightlip.git` → set Dependency Rule to **Up to Next Major** from `1.0.0`. (`Add Local...` also works for vendored checkouts.)
2. In the target's `Build Phases > Run Build Tool Plug-ins`, add **Lipservice**.
3. Create `<TargetName>/Secrets.yml` at the project root (the directory containing `.xcodeproj`). `<TargetName>` is the target's *display name*; the plugin resolves this path on the filesystem, not through Xcode's group tree, so the file's position in the Project Navigator is irrelevant. For a stock app template this is the `<TargetName>/` folder already at the top of the project.
4. Reference the generated enum anywhere in the target: `Secrets.revenueCatAPIKey`.

## Usage

Tightlip reads a single config file, `Secrets.yml`, in one of two formats. The format is auto-detected from the first non-comment line.

### Flat config

```yaml
# Secrets.yml
revenueCatAPIKey: REVENUECAT_API_KEY
hmacSigningKey:   HMAC_KEY
```

One line per secret: `<propertyName>: <ENV_VAR_NAME>`. The left side becomes a static property on `Secrets`; the right side names an environment variable resolved at build time.

### Sectioned config (multi-environment)

```yaml
# Secrets.yml
staging:
  revenueCatAPIKey: STAGING_REVENUECAT_API_KEY
  hmacSigningKey:   STAGING_HMAC_KEY

production:
  revenueCatAPIKey: PROD_REVENUECAT_API_KEY
  hmacSigningKey:   PROD_HMAC_KEY
```

Each top-level identifier followed by `:` (with no value) is an environment section. Lines within a section are indented exactly 2 spaces. All sections must declare the same set of property names. One section is selected per build — see [Environment selection](#environment-selection).

### Grammar

The parser is deliberately strict:

- Property names and env-var names must be bare ASCII identifiers (`[A-Za-z_][A-Za-z0-9_]*`). No quoting.
- `#` at the start of a line is a comment. Inline comments after a value are not supported.
- Blank lines are fine. Tabs are not — anywhere.
- Flat mode: no leading whitespace on mapping lines.
- Sectioned mode: section headers at column 1, content at exactly 2-space indent.
- Duplicate keys, empty files, and anything else outside this grammar are parse errors with a line number.

Every declared secret is required at build time. If an env var is unset, the build fails with a message pointing at the missing variable. Truly optional values should be read from `ProcessInfo` at runtime rather than declared here.

### Naming convention

Devs working on several apps on the same machine see bare names like `REVENUECAT_API_KEY` collide. Prefix every env var with an app-specific tag — `<APP_PREFIX>_<SECRET>` in screaming snake case (e.g. `ACME_REVENUECAT_API_KEY`). The plugin doesn't enforce this; the convention just keeps configs across projects from stepping on each other.

## Environment selection

When a sectioned config is used, the build tool picks one section in this order:

1. **`TIGHTLIP_ENV`** — if set, its value must match a section name exactly. Highest priority.
2. **Automatic inference** — when exactly two sections exist and one is named `prod` or `production`:
   - `CONFIGURATION=Release` (Xcode) → the `prod`/`production` section.
   - Any other configuration (including `Debug` and unset) → the other section.
3. **Error** — if neither rule resolves (e.g. three sections without `TIGHTLIP_ENV`), the build fails with a message listing available environments.

Flat configs have no environment concept and ignore all of this.

### Recommended setup

- **Local dev:** add `export TIGHTLIP_ENV=staging` to `~/.zshenv`, or leave it unset and let Debug builds pick the non-production section automatically.
- **CI release lane:** set `TIGHTLIP_ENV=production`, or rely on `CONFIGURATION=Release` if using Xcode.
- **More than two environments (qa, uat, etc.):** always set `TIGHTLIP_ENV` explicitly.

## Generated output

```swift
// Auto-generated by Tightlip. Do not edit.
// Regenerated on every build from environment variables.
// Environment: staging
import Foundation

nonisolated enum Secrets {
    static let appAPIKey: String = Self.decode("4qO9...")
    static let appBaseURL: String = Self.decode("9F2c...")

    private static let salt: [UInt8] = [0x12, 0x34, /* ...32 bytes... */]
    private static func decode(_ encoded: String) -> String { /* XOR + base64 */ }
}
```

Call sites see plain `String` (`Secrets.appAPIKey`). The stored bytes are XOR-encoded against a 32-byte salt derived deterministically from the resolved values, so identical inputs produce byte-identical output, which avoids spurious downstream recompiles. Plaintext literals never appear in the compiled binary; `strings` against the shipped `.app` won't surface them.

Properties are emitted in alphabetical order. The enum is always named `Secrets`. The `// Environment:` comment appears only for sectioned configs.

## Sourcing environment variables

By default the build tool sources `~/.zshenv` in a clean zsh subshell, captures the resulting environment, and merges it with `ProcessInfo.processInfo.environment` (the build's own env). Per-key conflicts resolve in favor of `ProcessInfo`, so CI runners and Xcode Scheme env vars override anything in `.zshenv`.

This behaves identically regardless of how the build was launched — Xcode.app from Finder, Conductor, VS Code, `xcodebuild` from Terminal. This eliminates the common case where an env var works in the shell but Xcode can't see it.

If the configured file doesn't exist (typical on CI), the tool falls back to `ProcessInfo` only. Sourcing failures and timeouts (5s default) also fall back, with a single note to stderr.

### Overriding the sourced file

Add a top-level `envFile:` directive before any secret declaration. The path is tilde-expanded against `$HOME`; relative paths resolve against the config's directory.

```yaml
envFile: ~/.bash_profile
revenueCatAPIKey: REVENUECAT_API_KEY
```

Per-shell recommendations:

| Shell | Recommended path | Notes |
|---|---|---|
| zsh | `~/.zshenv` *(default — directive can be omitted)* | Sourced cleanly with `zsh -f` |
| bash | `~/.bash_profile` or `~/.bashrc` | Sourced by zsh; shell-compatible `export` syntax works |
| fish | `~/.config/tightlip.env` *(sidecar)* | Fish syntax isn't zsh-compatible; keep a file of `export KEY=value` lines |
| nushell / xonsh / etc. | `~/.tightlip.env` *(sidecar)* | Same sidecar pattern as fish |

CI runners typically have no `.zshenv`; the tool falls back to `ProcessInfo` and the job's `env:` block works unchanged.

The directive is recognized only as the first non-blank, non-comment line. Anything after a section header or property mapping is parsed as a secret declaration.

## Troubleshooting

**`error: environment variable X must be set to generate Secrets.Y`** — the env var is unset in both the sourced file and `ProcessInfo`. The accompanying `note:` line lists everything visible with the same prefix (e.g. `*`), which usually points at a typo. Confirm the key exists in your `envFile` (default `~/.zshenv`).

**`note: sourcing /path/to/file ... using process environment only`** — the subshell that sources your `envFile` failed or timed out. Reproduce with `zsh -f -c 'source <yourEnvFile>'`. Typical causes: a tool inside `.zshenv` (e.g. `mise`, `asdf`) hitting something the sandbox blocks, or `.zshenv` taking longer than 5 seconds.

**`error: cannot determine environment: ...`** — a sectioned config is in use but the tool can't decide which section to build. Set `TIGHTLIP_ENV` to one of the listed names. This happens with more than two sections, or two sections where neither is named `prod`/`production`.

**`error: Secrets.yml:N: ...`** — the config didn't parse. Check the line against the [Grammar](#grammar) rules. Common causes: tab characters (paste from a different editor), quoted values, nested indentation, inline comments after a value.

**Plugin doesn't regenerate after changing an env var** — confirm you're looking at the right target. The plugin regenerates whenever the config file or env var values change between builds. If it seems stuck, run `xcodebuild clean` to force a fresh generation.

**Generated enum isn't visible in code** — confirm the plugin is attached to the target (Build Phases > Run Build Tool Plug-ins in Xcode) and that `Secrets.yml` is at the expected path.
