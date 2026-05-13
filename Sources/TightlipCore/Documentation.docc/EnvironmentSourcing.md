# How Environment Sourcing Works

Why your env vars resolve the same way whether you build from Xcode, the terminal, or CI.

## Overview

A common frustration with secret-via-env-var setups: the variable works in your shell, but Xcode can't see it. Or it works locally but not in CI. Or `~/.zshenv` exports something fine, but `xcodebuild` from a launcher doesn't pick it up.

Tightlip addresses this by sourcing your shell init file itself, in a controlled subshell, every build.

## The Algorithm

For each build, the plugin:

1. **Sources the env file in a clean zsh subshell.** By default this is `~/.zshenv`, sourced with `zsh -f` (no startup files, no profile chain). The subshell captures the resulting environment as a snapshot.
2. **Merges that snapshot with `ProcessInfo.processInfo.environment`** — the build's own environment, including Xcode Scheme env vars and CI job env vars.
3. **Resolves per-key conflicts in favor of `ProcessInfo`.** A CI runner that explicitly exports `APP_API_KEY` overrides anything `~/.zshenv` might have said.

The result: identical resolution regardless of how the build was launched. Xcode.app from Finder, Conductor, VS Code, `xcodebuild` from Terminal — same env vars seen, same generated file.

## Failure Modes

The subshell sourcing has a **5-second timeout**. If sourcing fails (the file doesn't exist, the file errors out, or it just takes too long), the tool falls back to `ProcessInfo` alone and writes a single `note:` to stderr identifying the file.

This means CI runners with no `~/.zshenv` work unchanged — the fallback kicks in immediately and the job's `env:` block is the sole source of values.

## Slow `.zshenv` Cases

Tools like `mise`, `asdf`, or `direnv` invoked during `.zshenv` can push past the 5-second budget. If you see the `note: sourcing /path/to/file ... using process environment only` message and weren't expecting it, reproduce with:

```bash
zsh -f -c 'source ~/.zshenv'
```

If that hangs or errors, your shell init is the cause. Move slow tools out of `.zshenv` (into `.zshrc`, which the plugin doesn't read), or point Tightlip at a smaller sidecar file with the [envFile directive](<doc:EnvFileDirective>).

## See Also

- <doc:EnvFileDirective>
- <doc:GettingStarted>
