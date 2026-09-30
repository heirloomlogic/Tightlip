<p align="center">
  <img src=".github/Tightlip-logo@2x.png" alt="Tightlip" width="256">
</p>

# Tightlip

A SwiftPM build-tool plugin that generates a typed Swift `Secrets` enum from environment variables at build time. The generated file lives in the plugin's work directory and is compiled into the consuming target. Secrets never enter source control.

[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue.svg)](https://heirloomlogic.github.io/Tightlip/documentation/tightlipcore/)

## Installation

### Swift Package Manager

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

Drop `Secrets.yml` at the target's source root (e.g. `Sources/MyApp/Secrets.yml`).

### Xcode project

1. `File > Add Package Dependencies...` → paste `https://github.com/heirloomlogic/Tightlip` → set Dependency Rule to **Up to Next Major** from `1.0.0`. (`Add Local...` also works for vendored checkouts.)
2. In the target's `Build Phases > Run Build Tool Plug-ins`, add **Lipservice**.
3. Create `<TargetName>/Secrets.yml` at the project root (the directory containing `.xcodeproj`). `<TargetName>` is the target's *display name*; the plugin resolves this path on the filesystem, not through Xcode's group tree, so the file's position in the Project Navigator is irrelevant. For a stock app template this is the `<TargetName>/` folder already at the top of the project. That folder is synchronized, so Xcode adds the new file to the target and would copy it into the app bundle: select `Secrets.yml`, open the File inspector, and clear its **Target Membership** checkbox. The plugin reads the file from disk and warns while it's still a member.
4. Reference the generated enum anywhere in the target: `Secrets.revenueCatAPIKey`.

## Agent skill

If you drive this setup with an AI coding assistant, install the `tightlip-ref` skill. It teaches the assistant how to integrate Tightlip, add or rename secrets, configure per-environment keys, and debug Lipservice build failures.

```bash
# Claude Code
gh skill install heirloomlogic/skills tightlip-ref --agent claude-code --force --scope user

# Codex
gh skill install heirloomlogic/skills tightlip-ref --agent codex --force --scope user
```

`--force` overwrites any existing copy, so re-run the same command to update to the latest version. `--scope user` installs the skill once for every project on the machine.

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
- An env-var name may end in `?` (`analyticsKey: ANALYTICS_KEY?`) to allow an empty value. The marker belongs to that one line, so in a sectioned config staging can allow an empty value while production requires one. No space before the `?`.
- Property names may not be Swift keywords (`class`, `default`, …; `open` is allowed), member names Swift rejects (`Type`, `Protocol`, `_`), names the generated enum reserves for itself (`salt`, `decode`, and `Swift` and `Foundation`, the module names its decode shim qualifies library symbols with), or the directive names `envFile` and `access` — any of these would produce a non-compiling or ambiguous generated file, so the parser rejects them up front. `Data`, `String`, `UTF8`, and the like are fine.
- `#` at the start of a line is a comment. Inline comments after a value are not supported.
- Blank lines are fine. Tabs are not — anywhere.
- Invisible characters (a no-break space pasted from Slack or Notion, a zero-width space, a stray carriage return) are parse errors, reported with their column. Comments and blank lines may contain anything.
- Flat mode: no leading whitespace on mapping lines.
- Sectioned mode: section headers at column 1, content at exactly 2-space indent.
- The `envFile:` and `access:` directives go at column 1 before the first section header or mapping, in either order, each at most once.
- Duplicate keys, empty files, and anything else outside this grammar are parse errors with a line number.

The full rules live in the [Config Grammar](https://heirloomlogic.github.io/Tightlip/documentation/tightlipcore/configgrammar) reference.

Every declared secret is required at build time. If an env var is unset or set to the empty string, the build fails with one `error:` line per variable, all of them in the same build. An empty value is usually a leftover `export KEY=` or a `$(…)` substitution that failed inside the build sandbox (see [Sourcing environment variables](#sourcing-environment-variables)). If empty is a legitimate value, mark the env-var name with `?`; the variable must still be set. Values that may be absent altogether should be read from `ProcessInfo` at runtime rather than declared here.

### Naming convention

Devs working on several apps on the same machine see bare names like `REVENUECAT_API_KEY` collide. Prefix every env var with an app-specific tag — `<APP_PREFIX>_<SECRET>` in screaming snake case (e.g. `ACME_REVENUECAT_API_KEY`). The plugin doesn't enforce this; the convention just keeps configs across projects from stepping on each other.

### Sharing secrets across modules

The generated enum and its properties are `internal` by default, so only the target that holds `Secrets.yml` can read them. In an app split into modules, where one secrets target feeds several feature targets, widen that with an `access:` directive at the top of the config:

```yaml
access: package
envFile: ./secrets.env
revenueCatAPIKey: ACME_REVENUECAT_API_KEY
```

The value is `internal` (the default), `package`, or `public`. Anything else, `public?` included, is a parse error. The keyword goes on the enum and on every property. The decode shim stays `private`.

- `package` makes `Secrets` visible to the other targets in the same SwiftPM package, and nowhere else. The secrets target and the targets that read it must all belong to one package, such as a local package that holds your app's modules.
- `public` makes `Secrets` visible to every module that imports the secrets target.

Either level widens the secrets module's API surface: every module that can see `Secrets` can read every value in it. The directive exists for module boundaries inside one app. It is not a way to publish secrets from a library other people depend on. Prefer `package` when your layout allows it, since it keeps the enum out of anything outside the package.

`access` is reserved as a secret name. With `internal`, the generated file is byte-identical to one from a config without the directive.

## Environment selection

When a sectioned config is used, the build tool picks one section in this order:

1. **`TIGHTLIP_ENV`** — if set (to a non-empty value), it must match a section name exactly. Highest priority.
2. **Automatic inference** — when exactly two sections exist and exactly one is named `prod` or `production`:
   - `CONFIGURATION=Release` (Xcode, `xcodebuild`, `swift build -c release`) → the `prod`/`production` section.
   - `CONFIGURATION=Debug` or unset → the other section.
   - Any other configuration name (`AppStore`, `Beta`, …) → the build fails; Tightlip refuses to guess which keys a custom configuration should get.
3. **Error** — if neither rule resolves (e.g. three sections without `TIGHTLIP_ENV`), the build fails with a message listing available environments.

Flat configs have no environment concept and ignore all of this.

### Recommended setup

- **Local dev:** add `export TIGHTLIP_ENV=staging` to `~/.zshenv`, or leave it unset and let Debug builds pick the non-production section automatically.
- **CI release lane:** set `TIGHTLIP_ENV=production`, or rely on `CONFIGURATION=Release`.
- **More than two environments (qa, uat, etc.) or custom Xcode configuration names:** always set `TIGHTLIP_ENV` explicitly. For custom configurations, add it as a user-defined build setting per configuration (Build Settings → + → Add User-Defined Setting), or pass it as an `xcodebuild` build-setting argument (`xcodebuild … TIGHTLIP_ENV=production`).

Xcode scheme environment variables (the Run action's Environment Variables) don't reach the plugin: they apply to running the app, not to building it.

> [!WARNING]
> Under SwiftPM's native build system (`--build-system native`, deprecated, and the default before Swift 6.4), `swift build -c release` does **not** set `CONFIGURATION`, so inference resolves to the *non*-production section — a release binary with staging keys. The default `swiftbuild` backend sets `CONFIGURATION` to `Release` or `Debug` to match `-c`. Either way, set `TIGHTLIP_ENV=production` explicitly on release lanes. The build log's `note: using environment '…'` line tells you what was picked.

## Generated output

```swift
// Auto-generated by Tightlip. Do not edit.
// Regenerated from environment variables when Secrets.yml or the env file changes.
// Environment: staging
import Foundation

nonisolated enum Secrets {
    static let appAPIKey: Swift.String = Self.decode("4qO9...")
    static let appBaseURL: Swift.String = Self.decode("9F2c...")

    private static let salt: [Swift.UInt8] = [0x12, 0x34, /* ...32 bytes... */]
    private static func decode(_ encoded: Swift.String) -> Swift.String { /* base64 + XOR */ }
}
```

Call sites see plain `String` (`Secrets.appAPIKey`). The shim spells library symbols module-qualified (`Swift.String`, `Foundation.Data`), so a type of your own named `Data` or `UTF8` can't break the generated file. The stored bytes are XOR-encoded against a 32-byte salt derived deterministically from the resolved values, so identical inputs produce byte-identical output; the tool leaves an unchanged file untouched, so it doesn't recompile. Plaintext literals never appear in the compiled binary; `strings` against the shipped `.app` won't surface them.

Properties are emitted in alphabetical order. The enum is always named `Secrets`. With `access: package` or `access: public`, that keyword leads the enum and every property (see [Sharing secrets across modules](#sharing-secrets-across-modules)). The `// Environment:` comment appears only for sectioned configs.

## Sourcing environment variables

By default the build tool sources `~/.zshenv` in a clean zsh subshell, captures the resulting environment, and merges it with the build environment — the variables the build itself runs with. Per-key conflicts resolve in favor of the build environment, so a CI job's `env:` block overrides anything in `.zshenv`.

The plugin copies every variable `Secrets.yml` names, plus `TIGHTLIP_ENV`, from its own environment into a 0600 file (`forwarded-environment`) in its work directory, and the tool reads it back. That's how CI `env:` variables reach the tool under SwiftPM's default `swiftbuild` backend (Swift 6.4+), which runs build commands in a synthesized environment. The tool's own process environment still wins per key over a forwarded value.

Xcode.app from Finder, Conductor, VS Code, and `xcodebuild` from Terminal all source the same file, which eliminates the common case where an env var works in the shell but Xcode can't see it. The exception is a launching process that exports a different value for a key the file sets — typically a terminal opened before the file was edited. The build environment wins, and the tool warns without printing either value:

```
warning: ACME_API_KEY from the build environment overrides the different value /Users/me/.zshenv exports; if the file is current, restart the terminal or Xcode session that launched this build
```

If the configured file doesn't exist (typical on CI), the tool uses the build environment only. Sourcing failures and timeouts (5s default) also fall back, with a single note to stderr; a file that errors *partway* still contributes the exports above the failing line, with a note that the capture may be partial.

The sourced file and the forwarded file are tracked as build inputs alongside `Secrets.yml`, and the plugin rewrites the forwarded file only when its contents change. Editing the env file, or changing `TIGHTLIP_ENV` or a declared variable's value in the build environment, re-runs generation on the next build — no clean needed.

The capture runs inside the build sandbox, where the Keychain (`securityd`), the 1Password CLI, the network, SSH agent sockets, and writes under `~` are unavailable. An env-file line like `export KEY=$(security find-generic-password … -w)` or `export KEY=$(op read …)` still exits 0 there and sets the key to the empty string, which fails the build with `error: environment variable KEY is set but empty; …`. Keep plain `export KEY=value` lines in a gitignored, 0600 sidecar file and point the [`envFile:` directive](#overriding-the-sourced-file) at it.

One caveat: `zsh -f` skips all startup files *except* the system-wide `/etc/zshenv`. On machines where IT tooling lives there (some managed Macs), that file runs during capture too — if sourcing is slow or noisy, check there as well as your own env file.

### Overriding the sourced file

Add a top-level `envFile:` directive before any secret declaration. A leading `~/` expands to your home directory; relative paths resolve against the config's directory. The path must name a file (not `~` or anything ending in `/`) and is taken literally: quotes, `$`, backticks, and `~user` are rejected rather than expanded. It may not contain spaces or `#`, and a bare identifier (`envFile: SOME_VAR`) is rejected as ambiguous with a secret mapping — write `./SOME_VAR`.

```yaml
envFile: ~/.bash_profile
revenueCatAPIKey: REVENUECAT_API_KEY
```

For non-zsh shells, point the directive at a file of zsh-compatible `export KEY=value` lines — `~/.bash_profile` works as-is for bash; fish and nushell users should keep a sidecar like `~/.tightlip.env`. Per-shell details are in the [envFile directive guide](https://heirloomlogic.github.io/Tightlip/documentation/tightlipcore/envfiledirective).

CI runners typically have no `.zshenv`; the tool uses the build environment alone and the job's `env:` block works unchanged.

The directive is recognized only before the first section header or property mapping. It may come before or after an `access:` directive. Anywhere later it is parsed as a secret declaration and fails.

### Project-local env file

Relative `envFile:` paths resolve against `Secrets.yml`'s directory, so `envFile: secrets.env` points at a sibling file inside the target:

```yaml
# Sources/MyApp/Secrets.yml
envFile: secrets.env
revenueCatAPIKey: ACME_REVENUECAT_API_KEY
```

The file is shell-sourced, so use `export KEY=value` syntax, **gitignore it**, and `chmod 600` it — only `Secrets.yml` belongs in source control.

**Keep it out of the app bundle.** In an Xcode project the target's folder is synchronized, so Xcode copies every non-source file in it — this one included, plaintext values and all — into the built app. Clear the file's **Target Membership** checkbox in the File inspector, or keep it outside the target's folder (`envFile: ../secrets.env`). The plugin fails the build while the env file is a bundle resource.

In a Swift package, exclude it from the target, or SwiftPM warns that it found an unhandled file:

```swift
.target(
    name: "MyApp",
    exclude: ["secrets.env"],
    plugins: [.plugin(name: "Lipservice", package: "Tightlip")]
)
```

Note that a project-local file must be re-created in every git worktree; a machine-global `~/.zshenv` is sourced identically across worktrees, which is usually what you want under Conductor.

Tightlip intentionally has no auto-discovered `.env` feature: the directive above already covers project-local files, and auto-discovery plus a bespoke dotenv parser would add an accidental-commit footgun and a value-parsing code path that shell-sourcing avoids.

## Troubleshooting

**`error: environment variable X must be set to generate Secrets.Y`** — the env var is unset in both the sourced file and the build environment. Every missing variable is reported in the same build, followed by a single `note: set the missing variable(s) in your shell, ~/.zshenv (for Xcode.app), or your CI environment`. The `note:` line above each error lists everything visible with the same prefix (e.g. `ACME_*`), which usually points at a typo. Confirm the key exists in your `envFile` (default `~/.zshenv`).

**`error: environment variable X is set but empty; Secrets.Y needs a value`** — usually a leftover `export KEY=`, or a `$(security …)` / `$(op read …)` substitution in the env file that failed inside the build sandbox. Use a literal value; see [Sourcing environment variables](#sourcing-environment-variables). If empty is intended, write the name as `X?` in `Secrets.yml`. Empty and missing variables are reported together in one build, followed by one `note:` of guidance for each kind.

**`warning: X from the build environment overrides the different value /path exports; …`** — the terminal or Xcode session that launched the build still exports an old value. If the file is current, restart it.

**`note: sourcing /path/to/file ... using the build environment only`** — the subshell that sources your `envFile` failed, timed out, or exited before finishing. Reproduce with `zsh -f -c 'source <yourEnvFile>'`. Typical causes: a tool inside `.zshenv` (e.g. `mise`, `asdf`) hitting something the sandbox blocks, or `.zshenv` taking longer than 5 seconds.

**`error: cannot determine environment: ...`** — a sectioned config is in use but the tool can't decide which section to build. Set `TIGHTLIP_ENV` to one of the listed names. This happens with more than two sections, two sections where neither is named `prod`/`production`, or a custom Xcode configuration name.

**`/path/to/Secrets.yml:N: error: ...`** — the config didn't parse; Xcode shows it as an issue on line N. Check the line against the [Grammar](#grammar) rules. Common causes: tab characters, a no-break space pasted from Slack or Notion (`invisible character U+00A0 NO-BREAK SPACE at column C; retype it as a plain space`), quoted values, nested indentation, inline comments after a value.

**`… is copied into the <Target> bundle as a resource`** — the target's synchronized folder would ship `Secrets.yml` (a warning: it names your env vars) or a project-local env file (an error: it holds the values) inside the app. Clear the file's **Target Membership** checkbox in the File inspector.

**`error: Tightlip config missing at …`** — the plugin is attached but `Secrets.yml` isn't where it looks: the target's source directory in a Swift package, or `<TargetName>/Secrets.yml` beside the `.xcodeproj` in an Xcode project.

**Plugin doesn't regenerate after changing an env var** — `Secrets.yml`, the sourced env file, and the build environment's values for `TIGHTLIP_ENV` and every declared variable are all tracked, so a change to any of them re-runs generation. If a change doesn't take, it probably never reached the build: Xcode.app keeps the environment it was launched with, scheme environment variables never reach the plugin, and a file your env file sources in turn isn't tracked (edit or `touch` the env file itself).

**Generated enum isn't visible in code** — confirm the plugin is attached to the target (Build Phases > Run Build Tool Plug-ins in Xcode) and that `Secrets.yml` is at the expected path.

More symptoms (partial env captures, CI-only failures, missing `envFile:` paths) are covered in the [Troubleshooting guide](https://heirloomlogic.github.io/Tightlip/documentation/tightlipcore/troubleshooting).
