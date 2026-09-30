# Troubleshooting

Symptom-to-fix table for the failure modes you'll hit integrating Tightlip.

## Overview

Every entry below is keyed on what you actually see in the build log. When a beautifier hides the real message, read <doc:ContinuousIntegration> first — the actionable error lives on the build phase's stderr, which `xcbeautify` and similar tools swallow.

To reproduce a failure without building, run `swift package tightlip-check`. It prints the same diagnostics, the selected section, and the state of every declared variable. See <doc:CheckingConfig>.

## Build and resolution failures

| Symptom | Cause | Fix |
|---|---|---|
| `error: environment variable X must be set to generate Secrets.Y` | The declared variable is unset in both the sourced env file and the build environment. Every missing variable is reported in the same build, each on its own `error:` line, followed by a single `note: set the missing variable(s) in your shell, ~/.zshenv (for Xcode.app), or your CI environment`. | Confirm the export in your `envFile` (default `~/.zshenv`), or set it on the CI job. Check the `note:` line above each error listing same-prefix variables visible to the build — usually a typo. Scheme environment variables don't reach the plugin. |
| `note: sourcing /path/to/file … using the build environment only` | The `zsh -f` subshell sourcing your env file failed, exceeded the 5-second timeout, or exited before dumping its environment (an `exit` inside the file). | Reproduce with `zsh -f -c 'source <yourEnvFile>'`. Common culprits: `mise`/`asdf`/`direnv` work inside `.zshenv`. Note `zsh -f` still sources the system-wide `/etc/zshenv` — on managed Macs, check there too. Keep `.zshenv` cheap, or point Tightlip at a sidecar via <doc:EnvFileDirective>. See <doc:EnvironmentSourcing>. |
| `note: sourcing /path/to/file reported exit status N; the captured environment may be partial` | The env file errored partway through — exports above the failing line resolved, exports below it did not. | Reproduce with `zsh -f -c 'source <yourEnvFile>'; echo $?` and fix the failing line. |
| `note: declared envFile not found at …` | `Secrets.yml` declares an `envFile:` that doesn't exist at the resolved path; the build used the build environment only. | Fix the path (relative paths resolve against `Secrets.yml`'s directory), or create the file. See <doc:EnvFileDirective>. |
| `note: /path/to/file is a directory; using the build environment only` (or `is not readable`) | The env file path resolves to a directory, or to a file the build can't read. | Point `envFile:` at a regular file and check its permissions. |
| `warning: X from the build environment overrides the different value /path/to/file exports; …` | The process that launched the build still exports an older value of `X` than the env file — typically a terminal opened before the file was edited, or an Xcode started from one. The build environment wins per key. Covers declared variables whose file value is non-empty; neither value is printed. (An overridden `TIGHTLIP_ENV` gets only a `note:`.) | If the file is current, restart the terminal or Xcode session that launched the build. |
| `error: cannot determine environment: …` | A sectioned config with no `TIGHTLIP_ENV`, and inference can't resolve it: 3+ sections, two sections where neither is named `prod`/`production`, or a `CONFIGURATION` that is neither `Debug` nor `Release` (a custom `AppStore`-style configuration — Tightlip refuses to guess which keys it should get). | Set `TIGHTLIP_ENV` to one of the listed environment names — as a user-defined build setting in Xcode, on the CI job, or in `~/.zshenv`. Scheme environment variables don't reach the plugin. See <doc:EnvironmentSelection>. |
| `/path/to/Secrets.yml:N: error: …` | A parse failure on line N; Xcode lists it as an issue on that line. | Check the line against <doc:ConfigGrammar>. Almost always a tab character, a quoted value, nested indentation, or an inline `# comment` after a value. |
| `/path/to/Secrets.yml:N: error: invisible character U+00A0 NO-BREAK SPACE at column C; retype it as a plain space` | The line holds a no-break space, usually from text pasted out of Slack or Notion. It looks identical to a plain space. | Retype the space at that column. Other invisible characters say `delete it`; a `stray carriage return` means bare-CR line endings somewhere in the file — save it with LF or CRLF endings. |
| `/path/to/Secrets.yml:N: error: section 'x' differs from 'y': missing …` | A sectioned config declares a property in one section but not another. Line N is section `x`'s header. | Add the missing property to every section (and export every corresponding env var), or remove it everywhere. |
| `<envFile> is copied into the <Target> bundle as a resource, which would ship its plaintext secrets` (build fails) | The env file sits in a synchronized Xcode folder (or a SwiftPM `resources:` rule), so the build would copy it into the product. | In Xcode, clear its **Target Membership** checkbox in the File inspector; in a Swift package, drop it from `resources:` and list it under `exclude:`. Or move it outside the target's folder and point `envFile:` at the new path. |
| `Secrets.yml is copied into the <Target> bundle as a resource` (warning) | Same cause: the target's synchronized folder adds `Secrets.yml` to Copy Bundle Resources, which ships the env-var names it declares. | Clear its **Target Membership** checkbox. The plugin reads the file from disk, not from the target. |
| `error: Tightlip config missing at …` | The plugin is attached but `Secrets.yml` isn't at the path it checks. | Create it there: in a Swift package, the target's source directory; in an Xcode project, `<TargetName>/Secrets.yml` beside the `.xcodeproj`, where `<TargetName>` is the target's display name. |
| `error: environment variable X is set but empty; Secrets.y needs a value` | The env var resolved to the empty string, and its line in `Secrets.yml` has no `?` marker. Usually a leftover `export KEY=`, or a `$(security …)` or `$(op read …)` substitution in the env file: inside the build sandbox it fails, exits 0, and yields `""`. Empty and missing variables are reported in the same build. | Use a literal `export KEY=value` in a gitignored, 0600 sidecar named by `envFile:` — see <doc:EnvironmentSourcing>. If empty is intended, write the name as `X?` in `Secrets.yml`; see <doc:ConfigGrammar>. |
| `Secrets` is an unresolved identifier at the call site | The plugin isn't attached to this target, or `Secrets.yml` isn't at the expected path. | Xcode: confirm **Lipservice** is under Build Phases → Run Build Tool Plug-ins. SwiftPM: confirm the `.plugin(…)` line is on this target. Confirm the `Secrets.yml` path — see <doc:GettingStarted>. |
| Plugin doesn't regenerate after changing an env var | `Secrets.yml`, the sourced env file, and the build environment's values for `TIGHTLIP_ENV` and every declared variable are all tracked, so a change to any of them re-runs generation. A change that doesn't take never reached the build: Xcode.app keeps the environment it was launched with, scheme environment variables never reach the plugin, and a file the env file sources in turn isn't tracked. | Put the export in the env file, or restart Xcode from a shell that has the new value. After editing a file your env file sources, edit or `touch` the env file itself. |

## CI-only failures

| Symptom | Cause | Fix |
|---|---|---|
| `PhaseScriptExecution Lipservice … failed` only in a simulator or test build | `-sdk iphonesimulator` forced the plugin's host tool to compile for the simulator, leaving no macOS slice for the build host to execute. | Drop `-sdk`; rely on `-destination` alone. Host tools then build for macOS. See <doc:ContinuousIntegration>. |
| `PhaseScriptExecution … failed` with no further detail on CI | A log beautifier (`xcbeautify` and similar) swallowed the plugin's stderr, where the real error lives. | Tee the raw log: `xcodebuild … 2>&1 \| tee raw.log \| xcbeautify`, then grep `raw.log` for `lipservice`, `secrets`, or `environment variable`. |
| Works locally, fails on CI with a missing-variable error | CI has no `~/.zshenv`; nothing exports the secret. | Set the variable in the CI job's environment. The plugin forwards it to the tool, including under SwiftPM's `swiftbuild` backend — no shell sourcing on CI. A test lane can use a dummy non-empty value. See <doc:ContinuousIntegration>. |

## See Also

- <doc:ContinuousIntegration>
- <doc:EnvironmentSourcing>
- <doc:ConfigGrammar>
