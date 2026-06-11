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

The path is tilde-expanded against `$HOME`; relative paths resolve against the config's directory. Only `~/` (your own home) is expanded — the `~user/file` form is not supported and would be treated as a relative path.

## Per-Shell Recommendations

| Shell | Recommended path | Notes |
|---|---|---|
| zsh | `~/.zshenv` *(default — directive can be omitted)* | Sourced cleanly with `zsh -f` |
| bash | `~/.bash_profile` or `~/.bashrc` | Sourced by zsh; shell-compatible `export` syntax works |
| fish | `~/.config/tightlip.env` *(sidecar)* | Fish syntax isn't zsh-compatible; keep a file of `export KEY=value` lines |
| nushell / xonsh / etc. | `~/.tightlip.env` *(sidecar)* | Same sidecar pattern as fish |

CI runners typically have no `.zshenv`; the tool falls back to `ProcessInfo` and the job's `env:` block works unchanged.

## Project-Local Env File

To keep a secrets file inside the project rather than your home directory, point the directive at a sibling of `Secrets.yml` — relative `envFile:` paths resolve against the config's directory:

```yaml
# Sources/MyApp/Secrets.yml
envFile: secrets.env
revenueCatAPIKey: ACME_REVENUECAT_API_KEY
```

```sh
# Sources/MyApp/secrets.env
export ACME_REVENUECAT_API_KEY="..."
```

The file is sourced in the same `zsh -f` subshell, so it must use `export KEY=value` syntax — not bare `KEY=value` dotenv lines.

**Gitignore it.** A secrets file inside the source tree is one `git add` away from a committed secret. Add it to `.gitignore`; only `Secrets.yml` — the manifest of env-var *names* — belongs in source control.

**Worktree caveat.** A project-local file lives inside each checkout, so every git worktree (and every fresh clone) needs its own copy. When you build the same project from multiple worktrees — e.g. parallel agents in Conductor — a single `~/.zshenv` is sourced identically by all of them, while a project-local file must be re-created per worktree. Prefer `~/.zshenv` (or a `~`-rooted sidecar) when worktree portability matters; use a project-local file only when you specifically want secrets scoped to one checkout.

## Why There's No Dedicated `.env` Feature

Tightlip deliberately doesn't auto-discover or parse a `.env` file. The recipe above already provides a project-local env file through the existing directive, so a dedicated feature would add only two things, both with costs:

- **Bare dotenv syntax** (`KEY=value` without `export`) would require parsing values ourselves. Today Tightlip never parses values — it sources a real shell and reads the result, delegating all quoting, escaping, and interpolation to zsh. A bespoke dotenv parser is new, security-sensitive surface with no agreed-on dialect across tools.
- **Auto-discovery** (reading a `.env` nobody configured) makes it easy to leak a secret into source control by accident and undercuts the core guarantee that only the manifest is tracked.

Want a project-local file? Use the directive above. Want machine-wide secrets every checkout and launcher sees identically? Use the default `~/.zshenv`. See <doc:EnvironmentSourcing> for why sourcing a shell beats parsing a file.

## See Also

- <doc:EnvironmentSourcing>
- <doc:ConfigGrammar>
