# Config Grammar

The accepted shape of `Secrets.yml`, line by line.

## Overview

Tightlip parses a small, strict subset of YAML. The parser rejects anything ambiguous so config errors fail loudly at build time instead of silently emitting the wrong value.

## Rules

- Property names and env-var names must be bare ASCII identifiers (`[A-Za-z_][A-Za-z0-9_]*`). No quoting.
- Property names may not be Swift keywords (`class`, `default`, …) or the names the generated enum reserves for its decode shim (`salt`, `decode`). Either would render a non-compiling generated file, so the parser rejects them with a line number instead.
- `#` at the start of a line is a comment. Inline comments after a value are not supported.
- Blank lines are fine. Tabs are not — anywhere.
- Flat mode: no leading whitespace on mapping lines.
- Sectioned mode: section headers at column 1, content at exactly 2-space indent.
- Every declared secret is required at build time. If an env var is unset, the build fails with a message pointing at the missing variable. Truly optional values should be read from `ProcessInfo` at runtime rather than declared here.
- Duplicate keys, empty files, and anything else outside this grammar are parse errors with a line number.

## Format Detection

The parser auto-detects format from the first non-comment line:

- If it has the shape `key: value`, the file is **flat**.
- If it has the shape `name:` (no value), the file is **sectioned**.

A single file cannot mix the two.

## Error Messages

Parse errors print as `<path>:<line>: <reason>`:

```
error: Secrets.yml:1: tab character not allowed; use spaces
error: Secrets.yml:1: expected '<name>: <ENV_VAR>', got 'foo BAR'
error: Secrets.yml:3: duplicate key 'foo' (first defined on line 1)
error: Secrets.yml:2: 'class' is a Swift keyword and cannot be used as a secret name
error: Secrets.yml: no secrets declared
```

The line number is omitted for whole-file errors like an empty config.

## Common Pitfalls

- **Tabs from a paste:** "expected '<name>: <ENV_VAR>'" usually means an invisible tab. Re-type the line.
- **Quoted values:** `foo: "BAR"` fails — quotes aren't accepted.
- **Inline comments:** `foo: BAR # comment` fails — comments are line-level only.
- **Hyphenated identifiers:** `revenue-cat-key: ...` fails — use camelCase Swift identifiers.

## See Also

- <doc:GettingStarted>
- <doc:SectionedConfigs>
