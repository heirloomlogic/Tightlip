# Sharing Secrets Across Modules

Widen the generated enum's access level with the `access:` directive so feature modules can read one secrets module.

## Overview

The generated `Secrets` enum and its properties are `internal` by default: only the target that holds `Secrets.yml` can read them. An app split into modules often keeps its secrets in one target and reads them from several feature targets. For that layout, declare an access level at the top of the config:

```yaml
access: package
envFile: ./secrets.env
revenueCatAPIKey: ACME_REVENUECAT_API_KEY
```

The generated file then reads:

```swift
package nonisolated enum Secrets {
    package static let revenueCatAPIKey: Swift.String = Self.decode("4qO9...")

    private static let salt: [Swift.UInt8] = [0x12, 0x34, /* ...32 bytes... */]
    private static func decode(_ encoded: Swift.String) -> Swift.String { /* base64 + XOR */ }
}
```

Feature targets import the secrets target and use `Secrets.revenueCatAPIKey` as they would inside it.

## Choosing a Level

| Value | Who can read `Secrets` |
|---|---|
| `internal` *(default)* | The target that holds `Secrets.yml` |
| `package` | Every target in the same SwiftPM package |
| `public` | Every module that imports the secrets target |

`package` needs the secrets target and the targets that read it to belong to one SwiftPM package, such as a local package that holds your app's modules. Swift scopes `package` access to a package, so a target outside it can't see the enum even if it imports the secrets target.

`public` has no such limit. Use it when the reading modules can't share a package with the secrets target.

With `internal`, the generated file is byte-identical to one from a config that has no `access:` line.

## What Widening Costs

Both `package` and `public` widen the secrets module's API surface. Every module that can see `Secrets` can read every value in it, and a new secret added to `Secrets.yml` becomes visible to all of them on the next build.

The directive is for module boundaries inside one app. It is not a way to publish secrets from a library other people depend on: anything compiled into a binary can be recovered from it (see <doc:Obfuscation>). Prefer `package` when your layout allows it, since it keeps the enum out of anything outside the package.

## Rules

- `access:` goes at column 1 before the first section header or mapping. It may come before or after `envFile:`, and each directive may appear once.
- The value must be exactly `internal`, `package`, or `public`. Anything else, including `public?`, `private`, `Public`, or a value followed by a comment, is a parse error with a line number.
- `access` is reserved: it can't be used as a secret name.
- The keyword applies to the enum and every property. The `salt` and `decode` helpers stay `private` at every level.

## See Also

- <doc:ConfigGrammar>
- <doc:EnvFileDirective>
- <doc:Obfuscation>
