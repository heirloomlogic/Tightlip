# Environment Selection

How Tightlip picks the active section for a sectioned config.

## Overview

When `Secrets.yml` declares multiple environment sections, exactly one is chosen per build. Tightlip applies these rules in order:

| Condition | Selected section |
|---|---|
| `TIGHTLIP_ENV` is set to a non-empty value | The section whose name matches exactly. Build fails if no section matches. |
| Two sections, exactly one named `prod` or `production`, and `CONFIGURATION=Release` | The `prod`/`production` section. |
| Two sections, exactly one named `prod` or `production`, and `CONFIGURATION=Debug` or unset | The non-production section. |
| Two sections, exactly one named `prod` or `production`, and any other `CONFIGURATION` (a custom configuration like `AppStore` or `Beta`) | Build fails — Tightlip refuses to guess which keys a custom configuration should get. Set `TIGHTLIP_ENV`. |
| Anything else (three sections without `TIGHTLIP_ENV`, two non-prod-named sections, or both `prod` *and* `production`) | Build fails with a message listing available environments. |

Flat configs have no environment concept and ignore all of this. An empty `TIGHTLIP_ENV` is treated as unset. Changing `TIGHTLIP_ENV` between builds re-runs generation on the next build, without a clean.

## Recommended Setup

- **Local dev:** add `export TIGHTLIP_ENV=staging` to `~/.zshenv`, or leave it unset and let Debug builds pick the non-production section automatically.
- **CI release lane:** set `TIGHTLIP_ENV=production`, or rely on `CONFIGURATION=Release`.
- **More than two environments (qa, uat, etc.):** always set `TIGHTLIP_ENV` explicitly — the two-section auto-inference doesn't fire.
- **Custom Xcode configuration names (`AppStore`, `Beta`, …):** set `TIGHTLIP_ENV` per configuration as a user-defined build setting (Build Settings → + → Add User-Defined Setting). Inference only recognizes the stock `Debug`/`Release` names.

In Xcode, `TIGHTLIP_ENV` reaches the plugin as a user-defined build setting, as a build-setting argument to `xcodebuild` (`xcodebuild … TIGHTLIP_ENV=production`), or through the environment of the process that launches `xcodebuild`. Scheme environment variables (the Run action's Environment Variables) don't work: they apply to running the app, not to building it.

> Warning: Under SwiftPM's native build system (`--build-system native`, deprecated, and the default before Swift 6.4), `swift build -c release` does **not** set `CONFIGURATION`, so inference resolves to the *non*-production section — a release binary with staging keys. The default `swiftbuild` backend sets `CONFIGURATION` to `Release` or `Debug` to match `-c`, as Xcode and `xcodebuild` do. Either way, set `TIGHTLIP_ENV=production` explicitly on release lanes. The build log's `note: using environment '…'` line tells you what was picked.

## Why `TIGHTLIP_ENV` Wins

The explicit env var always beats `CONFIGURATION` inference. This lets a single CI job override the default for a one-off release-candidate build without changing the project's build settings.

## See Also

- <doc:SectionedConfigs>
- <doc:EnvironmentSourcing>
