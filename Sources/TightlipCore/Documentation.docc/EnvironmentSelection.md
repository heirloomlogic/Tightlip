# Environment Selection

How Tightlip picks the active section for a sectioned config.

## Overview

When `Secrets.yml` declares multiple environment sections, exactly one is chosen per build. Tightlip applies these rules in order:

| Condition | Selected section |
|---|---|
| `TIGHTLIP_ENV` is set | The section whose name matches exactly. Build fails if no section matches. |
| Two sections, one named `prod` or `production`, and `CONFIGURATION=Release` | The `prod`/`production` section. |
| Two sections, one named `prod` or `production`, any other `CONFIGURATION` (including `Debug` and unset) | The non-production section. |
| Anything else (e.g. three sections without `TIGHTLIP_ENV`) | Build fails with a message listing available environments. |

Flat configs have no environment concept and ignore all of this.

## Recommended Setup

- **Local dev:** add `export TIGHTLIP_ENV=staging` to `~/.zshenv`, or leave it unset and let Debug builds pick the non-production section automatically.
- **CI release lane:** set `TIGHTLIP_ENV=production`, or rely on `CONFIGURATION=Release` if using Xcode.
- **More than two environments (qa, uat, etc.):** always set `TIGHTLIP_ENV` explicitly — the two-section auto-inference doesn't fire.

## Why `TIGHTLIP_ENV` Wins

The explicit env var always beats `CONFIGURATION` inference. This lets a single CI job override the default for a one-off release-candidate build without changing the project's Xcode scheme.

## See Also

- <doc:SectionedConfigs>
- <doc:EnvironmentSourcing>
