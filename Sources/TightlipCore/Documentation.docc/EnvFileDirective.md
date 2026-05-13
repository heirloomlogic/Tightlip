# Overriding the Sourced Env File

Point Tightlip at a different shell-init file with the `envFile:` directive.

## Overview

By default the build tool sources `~/.zshenv` to pick up your shell-exported env vars. If your shell isn't zsh, or your env-var exports live elsewhere, declare an `envFile:` directive at the top of `Secrets.yml`.

The directive must be the **first** non-blank, non-comment line. Anything after a section header or property mapping is parsed as a secret declaration and will fail.

## Syntax

```yaml
envFile: ~/.bash_profile
revenueCatAPIKey: REVENUECAT_API_KEY
```

The path is tilde-expanded against `$HOME`; relative paths resolve against the config's directory.

## Per-Shell Recommendations

| Shell | Recommended path | Notes |
|---|---|---|
| zsh | `~/.zshenv` *(default — directive can be omitted)* | Sourced cleanly with `zsh -f` |
| bash | `~/.bash_profile` or `~/.bashrc` | Sourced by zsh; shell-compatible `export` syntax works |
| fish | `~/.config/tightlip.env` *(sidecar)* | Fish syntax isn't zsh-compatible; keep a file of `export KEY=value` lines |
| nushell / xonsh / etc. | `~/.tightlip.env` *(sidecar)* | Same sidecar pattern as fish |

CI runners typically have no `.zshenv`; the tool falls back to `ProcessInfo` and the job's `env:` block works unchanged.

## See Also

- <doc:EnvironmentSourcing>
- <doc:ConfigGrammar>
