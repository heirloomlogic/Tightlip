# Config Grammar

The accepted shape of `Secrets.yml`, line by line.

## Overview

Tightlip parses a small, strict subset of YAML. The parser rejects anything ambiguous so config errors fail loudly at build time instead of silently emitting the wrong value.

## Rules

- Property names and env-var names must be bare ASCII identifiers (`[A-Za-z_][A-Za-z0-9_]*`). No quoting.
- An env-var name may end in `?`, written with no space before it (`analyticsKey: ANALYTICS_KEY?`), to allow an empty value. The marker applies to that line only: in a sectioned config, each section decides for itself.
- Property names may not be any of the following, which would render a non-compiling (or ambiguous) generated file; the parser rejects them with a line number instead:
  - Swift keywords (`class`, `default`, …; `open` is allowed) or the member names Swift rejects outright (`Type`, `Protocol`, `_`);
  - names the generated enum reserves for itself: `salt` and `decode`, used by its decode shim, and `Swift` and `Foundation`, the module names the shim qualifies library symbols with (`Swift.String`, `Foundation.Data`) so that neither a property nor a type of yours named `Data` or `UTF8` can shadow them;
  - `envFile`, which is reserved for the directive.
- `#` at the start of a line is a comment. Inline comments after a value are not supported — including after an `envFile:` path.
- Blank lines are fine. Tabs are not — anywhere.
- Invisible characters are rejected on every line that isn't blank or a comment: a no-break space, a zero-width space, any other format or control character, and a carriage return anywhere but the end of a line. Comments and blank lines may contain anything.
- The file must be UTF-8.
- Flat mode: no leading whitespace on mapping lines.
- Sectioned mode: section headers at column 1, content at exactly 2-space indent.
- Every declared secret is required at build time. If an env var is unset, or set to the empty string without a `?` marker, the build fails with one `error:` per variable, all reported in the same build. `?` does not make a variable optional: unset is still an error. Values that may be absent altogether should be read from `ProcessInfo` at runtime rather than declared here.
- Duplicate keys, empty files, and anything else outside this grammar are parse errors with a line number.

## Format Detection

The parser auto-detects format from the first non-comment line:

- If it has the shape `key: value`, the file is **flat**.
- If it has the shape `name:` (no value), the file is **sectioned**.

A single file cannot mix the two.

## Error Messages

Parse errors print as `<path>:<line>: error: <reason>`, the form Xcode attributes to the file and line, so each shows up as an issue you can click through to the offending line:

```
/path/to/Secrets.yml:1: error: tab character not allowed; use spaces
/path/to/Secrets.yml:1: error: expected '<name>: <ENV_VAR>', got 'foo BAR'
/path/to/Secrets.yml:3: error: duplicate key 'foo' (first defined on line 1)
/path/to/Secrets.yml:2: error: 'class' is a Swift keyword and cannot be used as a secret name
/path/to/Secrets.yml:1: error: invisible character U+00A0 NO-BREAK SPACE at column 5; retype it as a plain space
/path/to/Secrets.yml:1: error: invisible character U+200B ZERO WIDTH SPACE at column 9; delete it
/path/to/Secrets.yml:2: error: stray carriage return (U+000D) at column 9; save the file with LF or CRLF line endings
/path/to/Secrets.yml:4: error: section 'production' differs from 'staging': missing hmacSigningKey
/path/to/Secrets.yml: error: no secrets declared
/path/to/Secrets.yml: error: config is not valid UTF-8; save it with UTF-8 encoding
```

The line number is omitted for whole-file errors like an empty config. Section-level errors (an empty section, a duplicate section, sections that declare different properties) point at the section's header line.

## Common Pitfalls

- **Text pasted from Slack or Notion:** it often carries a no-break space where a plain space belongs. The line looks right but fails with `invisible character U+00A0 NO-BREAK SPACE at column N; retype it as a plain space`. Retype the space.
- **Quoted values:** `foo: "BAR"` fails — quotes aren't accepted.
- **Inline comments:** `foo: BAR # comment` fails — comments are line-level only.
- **Hyphenated identifiers:** `revenue-cat-key: ...` fails — use camelCase Swift identifiers.
- **A space before `?`:** `foo: BAR ?` fails. Write `foo: BAR?`.

## See Also

- <doc:GettingStarted>
- <doc:SectionedConfigs>
