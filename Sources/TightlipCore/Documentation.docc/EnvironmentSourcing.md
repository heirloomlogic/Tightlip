# How Environment Sourcing Works

Why your env vars resolve the same way whether you build from Xcode, the terminal, or CI.

## Overview

Env-var secret setups have a recurring failure mode: the variable works in your shell but Xcode can't see it, or it works locally but not in CI, or `~/.zshenv` exports it fine but `xcodebuild` from a launcher doesn't pick it up.

Tightlip addresses this by sourcing your shell init file itself, in a controlled subshell, every build.

## The Algorithm

For each build, the plugin:

1. **Sources the env file in a clean zsh subshell.** By default this is `~/.zshenv`, sourced with `zsh -f` (no startup files, no profile chain). The subshell captures the resulting environment as a snapshot.
2. **Merges that snapshot with the build environment** — the variables the build runs with: a CI job's `env:` block, the terminal that ran `swift build` or `xcodebuild`, Xcode build settings. Xcode scheme environment variables aren't among them; they apply to running the app, not to building it.
3. **Resolves per-key conflicts in favor of the build environment.** A CI runner that explicitly exports `APP_API_KEY` overrides anything `~/.zshenv` might have said.

The result: Xcode.app from Finder, Conductor, VS Code, and `xcodebuild` from Terminal all source the same file and see the same values from it. The exception is a launching process that exports a *different* value for a key the file sets. That happens when a terminal was opened before the file was edited: it still exports the old value, and the build environment wins per key. The tool warns for a declared variable, without printing either value (an empty file value, such as a `$(…)` that failed in the sandbox, isn't flagged); an overridden `TIGHTLIP_ENV` only gets a `note:`, since overriding it for one build is routine and the selected section is printed anyway:

```
warning: ACME_API_KEY from the build environment overrides the different value /Users/me/.zshenv exports; if the file is current, restart the terminal or Xcode session that launched this build
```

## Forwarding the Build Environment

SwiftPM's default `swiftbuild` backend (Swift 6.4+) runs build commands in a synthesized environment, so a variable exported by whoever started the build wouldn't reach the tool on its own. The plugin closes that gap. Each time it plans the build, it copies the variables `Secrets.yml` names (every right-hand identifier, in any section) plus `TIGHTLIP_ENV` from its own environment into `forwarded-environment`, a 0600 file in the plugin work directory, and the tool reads it back. Where the tool's own process environment also has a key, that value wins.

Values travel through a file rather than the build command's environment, which `xcodebuild` echoes into build logs. The file holds plaintext; see <doc:Obfuscation> for what that means for the build directory.

## Failure Modes

A missing default `~/.zshenv` is silent; a declared `envFile:` that doesn't exist gets a `note:`. Either way the build proceeds on the build environment alone.

The subshell sourcing has a **5-second timeout**. If sourcing fails outright — the path is a directory or unreadable, the shell exits non-zero, the file calls `exit` before the environment dump, or it takes too long — the tool falls back to the build environment alone and writes a single `note:` to stderr identifying the file.

If the file errors *partway* (say, a syntax error on one line), the exports above the failing line are still captured and used; a `note:` reports the exit status and warns that the environment may be partial. A missing variable in that situation usually means its `export` sits below the failing line.

This means CI runners with no `~/.zshenv` work unchanged — the fallback kicks in immediately and the job's `env:` block is the sole source of values.

The capture is insulated from the rest of what an env file can do:

- stdin is `/dev/null`, so a command that prompts for input gets end-of-file instead of waiting out the timeout.
- `EXIT` traps, `zshexit` hooks, and shell functions the file defines don't affect the environment dump.
- `setopt err_exit` in the file doesn't discard the exports above a failing line.
- An environment too large for `/usr/bin/env` to dump falls back with a note.
- A timeout kills the whole process group, including anything the file started in the background.
- A value that isn't valid UTF-8 is dropped with a note rather than embedded corrupted.

## Command Substitution Inside the Sandbox

The capture subshell runs inside the build sandbox. The Keychain (`securityd`), the 1Password CLI, the network, SSH agent sockets, and writes under `~` are all unavailable to it. A line like `export KEY=$(security find-generic-password … -w)` or `export KEY=$(op read …)` works in your terminal, but during the build the substitution fails, `export` still exits 0, and the key is set to the empty string. The build warns:

```
warning: ACME_API_KEY is set but empty; Secrets.acmeAPIKey will be ""
```

Keep plain `export KEY=value` lines in a sidecar file instead — gitignored, `chmod 600` — and point the [envFile directive](<doc:EnvFileDirective>) at it.

## Input Tracking

The sourced env file (the default `~/.zshenv` or the declared `envFile:`) is registered as a build input alongside `Secrets.yml`, so editing it re-triggers generation on the next build — no clean needed. So is `forwarded-environment`, which the plugin rewrites only when its contents change: changing `TIGHTLIP_ENV` or a declared variable's value in the build environment re-runs generation, in SwiftPM and `xcodebuild` alike, and an unchanged value doesn't.

Because the generated file is deterministic, a re-run that yields the same values produces byte-identical output, and the tool leaves the existing file untouched so nothing recompiles.

Only the env file itself is tracked. If it sources another file, edits to that file take effect on the next build that runs generation for some other reason; edit or `touch` the env file to force one.

## Slow `.zshenv` Cases

Tools like `mise`, `asdf`, or `direnv` invoked during `.zshenv` can push past the 5-second budget. If you see the `note: sourcing /path/to/file timed out after 5.0s; using the build environment only` message and weren't expecting it, reproduce with:

```bash
zsh -f -c 'source ~/.zshenv'
```

If that hangs or errors, your shell init is the cause. Move slow tools out of `.zshenv` (into `.zshrc`, which the plugin doesn't read), or point Tightlip at a smaller sidecar file with the [envFile directive](<doc:EnvFileDirective>).

## See Also

- <doc:EnvFileDirective>
- <doc:GettingStarted>
