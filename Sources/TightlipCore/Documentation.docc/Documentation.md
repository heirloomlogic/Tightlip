# ``TightlipCore``

A SwiftPM build-tool plugin that generates a typed Swift `Secrets` enum from environment variables at build time.

@Metadata {
    @DisplayName("Tightlip")
    @TitleHeading("Framework")
}

## Overview

![Tightlip logo](Tightlip-logo)

Tightlip reads a `Secrets.yml` config at the consuming target's source root, resolves each declared environment variable from the developer's shell or CI environment, and emits a Swift source file containing a `Secrets` enum. Stored values are XOR-encoded against a salt derived from the resolved values so identical inputs produce byte-identical generated files. Plaintext secrets never enter source control.

## Topics

### Essentials

- <doc:GettingStarted>

### How-To Guides

- <doc:SectionedConfigs>
- <doc:EnvFileDirective>

### Reference

- <doc:ConfigGrammar>
- <doc:EnvironmentSelection>

### Explanation

- <doc:Obfuscation>
- <doc:EnvironmentSourcing>

### Parsing

- ``ParsedSecret``
- ``ParsedConfig``
- ``ParsedConfigFile``
