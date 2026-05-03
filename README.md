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

One line per secret: `<propertyName>: <ENV_VAR_NAME>`. The left side becomes a static property on `Secrets`; the right side is looked up in `ProcessInfo.processInfo.environment` at build time.

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

nonisolated enum Secrets {
    static let edictAPIKey: String = "sk_test_..."
    static let edictBaseURL: String = "https://staging.edict.api..."
}
```

Properties are emitted in alphabetical order. The enum name is always `Secrets`; there is no way to override it per app. The `// Environment:` comment is included only for sectioned configs — flat configs omit it.

## Setting environment variables

The build tool reads `ProcessInfo.processInfo.environment` at build time — whatever populates that environment for your build process is what works. There's no shell-rc parsing inside the plugin. The recipe per launch context:

- **`xcodebuild` from Terminal:** `export FALLOW_REVENUECAT_API_KEY=...` in the shell that invokes `xcodebuild`.
- **Xcode.app launched via Finder/Dock:** set in `~/.zshenv` (read by GUI processes on login). Restart Xcode after editing.
- **Conductor, VS Code + SourceKit-LSP, and other agent/editor harnesses:** these typically spawn the build with a sanitized environment and do **not** source `~/.zshenv`. Set the vars in the harness config (Conductor's workspace env, VS Code's `settings.json` → `swift.environment`, etc.).
- **CI (GitHub Actions, Xcode Cloud, containerized runners):** export in the job's environment / secret block. `.zshenv` is not read.

Scheme environment variables under `Run` do **not** propagate to build phases; they only affect the launched app at runtime. Use `~/.zshenv` (Xcode.app) or the harness config (everything else) for build-time secrets.

## Troubleshooting

**`error: environment variable X must be set to generate Secrets.Y`** — the env var is unset. Follow the section above for your launch context.

**How do I know the env var is visible to the build?** Three quick checks, in order of reach:

- `launchctl getenv FALLOW_REVENUECAT_API_KEY` — what Xcode.app (and any launchd-spawned process) sees. Empty output means `~/.zshenv` hasn't been picked up; restart Xcode or re-log.
- Add a temporary Run Script build phase with `echo "FALLOW_REVENUECAT_API_KEY=${FALLOW_REVENUECAT_API_KEY}"` and read the build log — shows exactly what the build process inherits, regardless of launcher.
- For `xcodebuild` / SwiftPM CLI: `env | grep FALLOW_` in the invoking shell before running the build. If it's missing there, it won't be there for the build.

**`error: cannot determine environment: ...`** — a sectioned config is in use but the tool can't decide which section to build. Set `HEIRLOOM_ENV` to one of the listed environment names. This happens when you have more than two sections, or two sections where neither is named `prod`/`production`.

**`error: HeirloomSecrets.yml:N: ...`** — the config didn't parse. Check the line number against the grammar rules above. Common causes: tab characters (paste from a different editor), quoted values, nested indentation, inline comments after a value.

**Plugin doesn't regenerate after changing env var** — ensure you're looking at the right target. The plugin regenerates whenever the config file or env var values change between builds. If behavior seems stuck, run `xcodebuild clean` to force a fresh generation.

**Generated enum isn't visible in code** — confirm the plugin is attached to the target (Build Phases > Run Build Tool Plug-ins in Xcode), and that `HeirloomSecrets.yml` is at the expected path.
