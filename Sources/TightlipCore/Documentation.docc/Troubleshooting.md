# Troubleshooting

Symptom-to-fix table for the failure modes you'll hit integrating Tightlip.

## Overview

Every entry below is keyed on what you actually see in the build log. When a beautifier hides the real message, read <doc:ContinuousIntegration> first — the actionable error lives on the build phase's stderr, which `xcbeautify` and similar tools swallow.

## Build and resolution failures

| Symptom | Cause | Fix |
|---|---|---|
| `error: environment variable X must be set to generate Secrets.Y` | The declared variable is unset in both the sourced env file and the build's own environment. | Confirm the export in your `envFile` (default `~/.zshenv`), or set it in the scheme / CI job. Check the `note:` line listing same-prefix variables visible to the build — usually a typo. Re-source the file or restart Xcode. |
| `note: sourcing /path/to/file … using process environment only` | The `zsh -f` subshell sourcing your env file failed or exceeded the 5-second timeout. | Reproduce with `zsh -f -c 'source <yourEnvFile>'`. Common culprits: `mise`/`asdf`/`direnv` work inside `.zshenv`. Note `zsh -f` still sources the system-wide `/etc/zshenv` — on managed Macs, check there too. Keep `.zshenv` cheap, or point Tightlip at a sidecar via <doc:EnvFileDirective>. See <doc:EnvironmentSourcing>. |
| `error: cannot determine environment: …` | A sectioned config with no `TIGHTLIP_ENV`, and inference can't resolve it (3+ sections, or two sections where neither is named `prod`/`production`). | Set `TIGHTLIP_ENV` to one of the listed environment names — in the scheme, on the CI job, or in `~/.zshenv`. See <doc:EnvironmentSelection>. |
| `error: Secrets.yml:N: …` | A parse failure on line N. | Check the line against <doc:ConfigGrammar>. Almost always a tab character, a quoted value, nested indentation, or an inline `# comment` after a value. |
| `error: sections must declare the same properties` | A sectioned config declares a property in one section but not another. | Add the missing property to every section (and export every corresponding env var), or remove it everywhere. |
| `Secrets` is an unresolved identifier at the call site | The plugin isn't attached to this target, or `Secrets.yml` isn't at the expected path. | Xcode: confirm **Lipservice** is under Build Phases → Run Build Tool Plug-ins. SwiftPM: confirm the `.plugin(…)` line is on this target. Confirm the `Secrets.yml` path — see <doc:GettingStarted>. |
| Plugin doesn't regenerate after changing an env var | The plugin's input tracking keys on `Secrets.yml`, not on env-var values, or you're looking at a stale build. | Clean the build (`xcodebuild clean`, or Product → Clean Build Folder) to force regeneration. |

## CI-only failures

| Symptom | Cause | Fix |
|---|---|---|
| `PhaseScriptExecution Lipservice … failed` only in a simulator or test build | `-sdk iphonesimulator` forced the plugin's host tool to compile for the simulator, leaving no macOS slice for the build host to execute. | Drop `-sdk`; rely on `-destination` alone. Host tools then build for macOS. See <doc:ContinuousIntegration>. |
| `PhaseScriptExecution … failed` with no further detail on CI | A log beautifier (`xcbeautify` and similar) swallowed the plugin's stderr, where the real error lives. | Tee the raw log: `xcodebuild … 2>&1 \| tee raw.log \| xcbeautify`, then grep `raw.log` for `lipservice`, `secrets`, or `environment variable`. |
| Works locally, fails on CI with a missing-variable error | CI has no `~/.zshenv`; nothing exports the secret. | Set the variable in the CI job's environment. The plugin reads it directly from `ProcessInfo` — no shell sourcing on CI. A test lane can use a dummy non-empty value. See <doc:ContinuousIntegration>. |

## See Also

- <doc:ContinuousIntegration>
- <doc:EnvironmentSourcing>
- <doc:ConfigGrammar>
