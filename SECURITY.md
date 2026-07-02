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

Two properties of the design deserve explicit attention when reviewing changes to a project that uses Tightlip:

- **`Secrets.yml` chooses which environment variables get embedded in the build product.** A pull request that edits `Secrets.yml` to map a property onto a CI credential (say, `key: AWS_SECRET_ACCESS_KEY`) exfiltrates that credential through the built artifact itself — no code execution or network access required. Review `Secrets.yml` diffs with the same care as code, and build untrusted pull requests with a minimal environment.
- **The `envFile:` directive names a file that is executed (shell-sourced) at build time.** Inside SwiftPM's plugin sandbox this is no more power than any build-tool plugin already has, but builds run with `--disable-sandbox` (a common workaround on some CI images) turn a repository-controlled `envFile: ./x.sh` into unsandboxed shell execution. Don't disable the sandbox when building repositories you don't trust.

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
