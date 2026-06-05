# Running Tightlip in CI

Wire the plugin into every lane that compiles your target, and avoid the build-host trap that only shows up in simulator builds.

## Overview

The Lipservice plugin runs as a build-tool phase, so it fires on **every** `xcodebuild` (or `swift build`) invocation that compiles the attached target — `build`, `test`, and `archive` alike. Each of those lanes needs the declared environment variables, and one of them has a platform trap that the others don't. This guide covers the three things that bite first-time CI setups.

## Provide the env vars on every lane that compiles the target

A build fails the moment a declared secret is unresolved, regardless of why the build was launched:

```
error: environment variable ACME_API_KEY must be set to generate Secrets.acmeAPIKey.
```

It's easy to set the secret on the distribution lanes and forget the unit-test lane, because tests feel unrelated to secrets. They aren't — compiling the target runs the plugin.

Enumerate the jobs that compile the target and supply the secret in **each** of them:

- Archive / distribution lanes (TestFlight, Firebase) — the real production secret.
- Build lanes.
- **Unit-test lanes** — the one people forget.

A lane that doesn't compile the target is exempt. A SwiftLint-only or formatting-only job, for instance, never invokes the plugin.

### Use a dummy value on test lanes

Test lanes almost never exercise the secret at runtime — they just need *something* non-empty so the build resolves. Supply a dummy value there and keep the real production secret confined to the artifact-uploading distribution workflow, which runs less often and has a smaller blast radius:

```yaml
- name: Run unit tests
  env:
    ACME_API_KEY: dummy-value-for-tests   # tests don't use the real secret
  run: xcodebuild test …
```

CI runners have no `~/.zshenv`, so the plugin reads these values straight from the job's environment via `ProcessInfo` with no shell sourcing involved. See <doc:EnvironmentSourcing>.

## Don't pass `-sdk iphonesimulator` — use `-destination` alone

This is the one that costs the most time, because it surfaces only in simulator builds (typically the unit-test lane) and the error points nowhere useful.

**Symptom.** A simulator or test build dies with a generic phase failure and no actionable detail:

```
PhaseScriptExecution Lipservice\ (MyApp) … failed with a nonzero exit code
```

**Cause.** `LipserviceTool`, the executable the plugin runs, is a **host tool** — it must run on the machine doing the build, i.e. macOS. Passing `-sdk iphonesimulator` forces *every* product, including the plugin's host tool, to compile for the iOS simulator. The result has only simulator slices and no macOS slice, so the build host can't execute it, and the build-tool phase fails (a "Bad CPU type in executable"-class error).

This is the generic "SwiftPM plugin or macro built for the target platform instead of the host" trap. It tends to look like "only the tests are broken," because archive and distribution lanes don't pass `-sdk` and keep working — which sends you debugging the test setup instead of the SDK flag.

**Fix.** Drop `-sdk`. `-destination` fully selects the simulator on its own, while letting host tools build for macOS:

```diff
  xcodebuild test -scheme MyApp -configuration Debug \
-   -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=iPhone 17,OS=26.4.1" …
```

This repository's own CI uses exactly this pattern: the `build-ios` job in `.github/workflows/test.yml` builds with `-destination 'generic/platform=iOS Simulator'` and no `-sdk`, precisely to keep the plugin's host tool building for macOS.

## Capture the raw log — beautifiers hide the real error

The plugin emits its actionable error (missing variable, parse failure, the host-tool exec failure above) on the build phase's stderr. Log beautifiers such as `xcbeautify` swallow that stream and surface only the generic `PhaseScriptExecution … failed`, so CI looks blind.

Tee the raw output before beautifying, then grep it:

```bash
xcodebuild … 2>&1 | tee raw.log | xcbeautify
grep -i "secrets\|environment variable\|lipservice" raw.log
```

The real Tightlip error — the line that tells you what to fix — lives in `raw.log`.

## See Also

- <doc:Troubleshooting>
- <doc:EnvironmentSourcing>
- <doc:EnvironmentSelection>
