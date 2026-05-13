# Security Policy

## Supported Versions

Tightlip follows semantic versioning. Security fixes are applied to the latest minor release line. Older release lines are not maintained.

## Reporting a Vulnerability

If you believe you have found a security issue in Tightlip, please **do not** open a public GitHub issue. Instead, email tightlip@heirloomlogic.com with:

- A description of the issue and its impact
- Steps to reproduce
- Any suggested remediation

You can expect an acknowledgement within a few business days. Once the issue is confirmed, we will coordinate a fix and a disclosure timeline with you.

## Threat Model

Tightlip is a build-time code generator. It reads a developer-authored config file (`Secrets.yml`), resolves environment-variable values from the developer's shell environment or CI environment, and emits a Swift source file that is compiled into the consuming target. It performs no network I/O and processes no untrusted input at runtime.

The XOR-encoded literal output is a **defense against `strings`-style trivial extraction** from the shipped binary, not encryption. A determined attacker with the binary and a debugger can recover any secret embedded in any app — Tightlip is not, and cannot be, a substitute for a secret-management service for high-value credentials. Treat the generated `Secrets` enum the same way you would treat any compile-time constant in your binary.

Plausible in-scope security issues:

- Path traversal or arbitrary file read via `envFile:` directive
- Command injection in the zsh subprocess that sources `~/.zshenv`
- Sensitive values appearing in build logs, error output, or temporary files
- Race conditions in the build-tool plugin work directory

Out of scope:

- "An attacker with the binary can recover the secrets" — yes; see above.
- Secrets present in `~/.zshenv` or other developer-machine env-var sources being read by the plugin — that is the design.
- Upstream Persnicket or swift-format issues — report those to their respective projects.

Reports on cosmetic issues or DocC content should be filed as regular GitHub issues.
