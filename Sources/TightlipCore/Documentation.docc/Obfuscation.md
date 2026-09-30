# Obfuscation and Threat Model

What the XOR encoding actually protects against, and what it doesn't.

## Overview

The generated `Secrets` enum stores each value as XOR-encoded bytes, decoded on first access:

```swift
nonisolated enum Secrets {
    static let appAPIKey: Swift.String = Self.decode("4qO9...")

    private static let salt: [Swift.UInt8] = [0x12, 0x34, /* ...32 bytes... */]
    private static func decode(_ encoded: Swift.String) -> Swift.String { /* base64 + XOR */ }
}
```

Call sites see plain `String`. The encoded literal is what the compiler stores in the binary.

## What Obfuscation Buys You

**`strings` resistance.** Running `strings MyApp.app/Contents/MacOS/MyApp` (or its iOS equivalent) won't surface your API keys. The bytes on disk are XOR-encoded against a 32-byte salt; without running the `decode` function you only see ciphertext.

This blocks the laziest class of secret extraction: someone unzipping a shipped binary and grepping for keys.

## What It Doesn't Buy You

A determined attacker with the binary and a debugger can recover any compile-time constant from any app — yours included. Setting a breakpoint after `decode` runs, or simply running the binary and reading process memory, defeats this in seconds.

> "The XOR-encoded literal output is a **defense against `strings`-style trivial extraction** from the shipped binary, not encryption. A determined attacker with the binary and a debugger can recover any secret embedded in any app — Tightlip is not, and cannot be, a substitute for a secret-management service for high-value credentials. Treat the generated `Secrets` enum the same way you would treat any compile-time constant in your binary." — `SECURITY.md`

The build directory is exposed too. The generated file sits in the plugin work directory with every value in reversible form, and beside it `forwarded-environment` holds the plaintext values of every section's declared variables that were set in the build environment (the plugin writes it with 0600 permissions, and can't know which section the tool will select). Treat the build directory — `.build`, DerivedData, and any CI cache of either — as secret-bearing.

If a credential is high-value enough that compromise is a meaningful threat, fetch it from a secret-management service at runtime. Don't ship it in the binary at all.

The full threat model — including in-scope and out-of-scope security issues — lives in [`SECURITY.md`](https://github.com/heirloomlogic/Tightlip/blob/main/SECURITY.md).

## Why Determinism Matters

The salt is derived deterministically from the resolved values. Identical inputs produce byte-identical generated files. Without this, every build would write a different file and force a downstream recompile even when no actual secret changed. That would slow every incremental build. The tool also skips the write when the contents haven't changed, so the file's timestamp stays put.

## See Also

- <doc:EnvironmentSourcing>
