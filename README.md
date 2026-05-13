<p align="center">
  <img src=".github/HeirloomSecrets-logo@2x.png" alt="HeirloomSecrets" width="256">
</p>

<p align="center">
SwiftPM build-tool plugin that generates a typed Swift enum of secrets from environment variables at build time.<br>
Secrets never live in source control — the generated file lands in the plugin's work directory and is compiled into the consuming target.
</p>

## Why

Each Heirloom Logic app needs its own API keys (RevenueCat, HMAC, etc.). Without this plugin, every app reinvents the mechanism (shell script + gitignore entry + build phase). With it, adoption is declarative: add the plugin and drop a small YAML config.

## Adoption

### Versioning (pre-1.0)

HeirloomSecrets has no tagged releases yet, so Xcode's "Up to Next Major" / "Exact Version" rules won't resolve against this repo. If you add it as a remote Swift package dependency:

- **Xcode GUI:** `File > Add Package Dependencies...` → paste the repo URL → set Dependency Rule to **Branch** → `main`.
- **Package.swift:** `.package(url: "https://github.com/heirloomlogic/HeirloomSecrets.git", branch: "main")`.

Switch to a version rule once 1.0.0 is cut. Local references (`Add Local...`) are unaffected and work today.

### Xcode project

1. Add the package as a local reference (`File > Add Package Dependencies... > Add Local...`), pointing at `HeirloomSecrets/` — or use the remote `branch = main` setup from the Versioning note above.
2. In the target's `Build Phases > Run Build Tool Plug-ins`, add `InjectHeirloomSecrets`.
3. Create `<TargetName>/HeirloomSecrets.yml` at the project root (the directory containing `.xcodeproj`). `<TargetName>` here is the target's *display name* — the plugin resolves this path on the filesystem using the display name, not through Xcode's group tree, so the file's location in the Project Navigator is irrelevant. In a stock project created from Xcode's app template this is just the `<TargetName>/` folder already at the top of the project. (See format below.)
4. Reference the generated enum anywhere in your target: e.g. `Secrets.revenueCatAPIKey`.

### SwiftPM package

```swift
.target(
    name: "MyApp",
    plugins: [.plugin(name: "InjectHeirloomSecrets", package: "HeirloomSecrets")]
)
```

Then drop `HeirloomSecrets.yml` at the target's source root (`Sources/MyApp/HeirloomSecrets.yml`).

## Config format

HeirloomSecrets supports two config formats, auto-detected from the first non-comment line.

### Flat format

```yaml
# HeirloomSecrets.yml
revenueCatAPIKey: FALLOW_REVENUECAT_API_KEY
hmacSigningKey:   FALLOW_HMAC_KEY
```

One line per secret: `<propertyName>: <ENV_VAR_NAME>`. The left side becomes a static property on `Secrets`; the right side names an environment variable. At build time the tool sources `~/.zshenv` (override below), captures its environment, layers `ProcessInfo` on top per key, and looks up each name in the merged result.

### Sectioned format (multi-environment)

```yaml
# HeirloomSecrets.yml
staging:
  edictAPIKey: FALLOW_STAGING_EDICT_KEY
  edictBaseURL: FALLOW_STAGING_EDICT_URL

production:
  edictAPIKey: FALLOW_PROD_EDICT_KEY
  edictBaseURL: FALLOW_PROD_EDICT_URL
```

Each top-level identifier followed by `:` (with no value) is an environment section. Lines within a section are indented exactly 2 spaces. All sections must declare the same set of property names.

At build time, the tool selects one section and generates secrets from it. See **Environment selection** below.

### Grammar rules

The parser is deliberately strict — it accepts these shapes and little else:

- Both property names and env-var names must be bare ASCII identifiers (`[A-Za-z_][A-Za-z0-9_]*`). No quoting syntax.
- `#` at the start of a line is a comment. Inline comments after values aren't supported.
- Blank lines are fine. No tabs anywhere.
- In flat mode: no leading whitespace on mapping lines.
- In sectioned mode: section headers at column 1, content at exactly 2-space indent.
- Duplicate keys, empty files, and anything else outside this grammar are parse errors with a line number.

Every declared secret is required at build time. If an env var is unset, the build fails with a message pointing at the missing variable. For keys that should be truly optional, read them from `ProcessInfo` at runtime instead of declaring them here.

### Naming convention

Heirloom Logic devs often have several apps checked out on the same machine, and bare names like `REVENUECAT_API_KEY` will collide across them. Prefix every env var with the app: `<APP_PREFIX>_<SECRET>` in screaming snake case — e.g. `FALLOW_REVENUECAT_API_KEY`, `ADAGIO_REVENUECAT_API_KEY`. The plugin doesn't enforce this (the env var string is passed straight to `ProcessInfo`), but every shipping Heirloom app follows it; do the same in new configs.

## Environment selection

When a sectioned config is used, the build tool determines which section to resolve:

1. **`HEIRLOOM_ENV`** — if set, its value must match a section name exactly. This takes highest priority.
2. **Automatic inference** — when exactly two sections exist and one is named `prod` or `production`:
   - Xcode's `CONFIGURATION=Release` → selects the `prod`/`production` section.
   - Any other configuration (including `Debug` and unset) → selects the other section.
3. **Error** — if neither mechanism resolves (e.g. three sections without `HEIRLOOM_ENV`), the build fails with a message listing available environments.

Flat configs ignore all of this — there's no environment concept to resolve.

### Recommended setup

- **Local dev:** add `export HEIRLOOM_ENV=staging` to `~/.zshenv` (or leave it unset — Debug builds infer the non-production section automatically).
- **CI release lane:** set `HEIRLOOM_ENV=production` (or rely on `CONFIGURATION=Release` if using Xcode).
- **Multiple non-production environments (qa, uat, etc.):** always set `HEIRLOOM_ENV` explicitly.

## Generated output

```swift
// Auto-generated by HeirloomSecrets. Do not edit.
// Regenerated on every build from environment variables.
// Environment: staging
import Foundation

nonisolated enum Secrets {
    static let edictAPIKey: String = Self.decode("4qO9...")
    static let edictBaseURL: String = Self.decode("9F2c...")

    private static let salt: [UInt8] = [0x12, 0x34, /* ...32 bytes... */]
    private static func decode(_ encoded: String) -> String { /* XOR + base64 */ }
}
```

Call sites still see plain `String` (`Secrets.edictAPIKey`); the stored bytes are XOR-encoded against a 32-byte salt derived deterministically from the resolved values, so identical inputs produce byte-identical output (no spurious downstream recompiles). Plaintext literals never appear in the compiled binary — `strings` against the shipped `.app` won't surface them.

Properties are emitted in alphabetical order. The enum name is always `Secrets`. The `// Environment:` comment is included only for sectioned configs.

## Sourcing environment variables

By default the build tool sources `~/.zshenv` in a clean zsh subshell, captures the resulting environment, and merges it with `ProcessInfo.processInfo.environment` (the build's own env). Per-key conflicts resolve in favor of `ProcessInfo`, so CI runners and Xcode Scheme env vars override anything in `.zshenv`.

This works the same way regardless of how the build was launched — Xcode.app from Finder, Conductor, VS Code, `xcodebuild` from Terminal. The whole class of "my env var works in the shell but Xcode can't see it" goes away.

If the configured file doesn't exist (typical on CI), the tool falls back to `ProcessInfo` only. Sourcing failures and timeouts (5s default) also fall back, with a single note to stderr.

### Overriding the sourced file

Add a single top-level `envFile:` directive before any secret declaration. Path is tilde-expanded against `$HOME`; relative paths resolve against the config's directory.

```yaml
envFile: ~/.bash_profile
revenueCatAPIKey: FALLOW_REVENUECAT_API_KEY
```

Per-shell choice for `envFile:`:

| Shell | Recommended path | Notes |
|---|---|---|
| zsh | `~/.zshenv` *(default — directive can be omitted)* | Sourced cleanly with `zsh -f` |
| bash | `~/.bash_profile` or `~/.bashrc` | Sourced by zsh; shell-compatible `export` syntax works |
| fish | `~/.config/heirloom-secrets.env` *(sidecar)* | Fish syntax isn't zsh-compatible; keep a small file of `export KEY=value` lines |
| nushell / xonsh / etc. | `~/.heirloom-secrets.env` *(sidecar)* | Same sidecar pattern as fish |

CI runners typically have no `.zshenv`; the tool falls back to `ProcessInfo` and your job's `env:` block works unchanged.

The directive is recognized only as the first non-blank, non-comment line. Anything after a section header or property mapping is parsed as a secret declaration.

## Troubleshooting

**`error: environment variable X must be set to generate Secrets.Y`** — the env var is unset in both the sourced file and `ProcessInfo`. The accompanying `note:` line lists everything visible with the same prefix (e.g. `FALLOW_*`), which usually points at a typo. Confirm the key exists in your `envFile` (default `~/.zshenv`) with `grep` or `cat`.

**`note: sourcing /path/to/file ... using process environment only`** — the subshell that sources your envFile failed or timed out. Run `zsh -f -c 'source <yourEnvFile>'` in a terminal to reproduce. Typical causes: a tool inside `.zshenv` (e.g. `mise`, `asdf`) hitting something the sandbox blocks, or `.zshenv` taking longer than 5 seconds to run.

**`error: cannot determine environment: ...`** — a sectioned config is in use but the tool can't decide which section to build. Set `HEIRLOOM_ENV` to one of the listed environment names. This happens when you have more than two sections, or two sections where neither is named `prod`/`production`.

**`error: HeirloomSecrets.yml:N: ...`** — the config didn't parse. Check the line number against the grammar rules above. Common causes: tab characters (paste from a different editor), quoted values, nested indentation, inline comments after a value.

**Plugin doesn't regenerate after changing env var** — ensure you're looking at the right target. The plugin regenerates whenever the config file or env var values change between builds. If behavior seems stuck, run `xcodebuild clean` to force a fresh generation.

**Generated enum isn't visible in code** — confirm the plugin is attached to the target (Build Phases > Run Build Tool Plug-ins in Xcode), and that `HeirloomSecrets.yml` is at the expected path.
