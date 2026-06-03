# Agent Skill

Install the `tightlip-ref` skill so your AI coding assistant knows how to work with Tightlip.

## Overview

`tightlip-ref` is an agent skill published in the `heirloomlogic/skills` repository. It teaches AI coding assistants — Claude Code and Codex — the setup steps and code patterns for Tightlip: integrating the plugin into a new target, adding or renaming secrets, configuring per-environment keys, placing `Secrets.yml`, and debugging Lipservice build failures.

Install it with the `gh skill` extension.

## Installation

### Claude Code

```bash
gh skill install heirloomlogic/skills tightlip-ref --agent claude-code --force --scope user
```

### Codex

```bash
gh skill install heirloomlogic/skills tightlip-ref --agent codex --force --scope user
```

`--scope user` installs the skill once for every project on the machine.

## Updating

Re-run the install command for your agent. `--force` overwrites the existing copy with the latest version, so the install command is also the update command.

## See Also

- <doc:GettingStarted>
