import CryptoKit
import Foundation

/// A single secret declared in a Tightlip YAML config.
public struct ParsedSecret: Equatable, Sendable {
    /// The Swift property name emitted on the generated `Secrets` enum.
    public let name: String

    /// The environment variable the build tool reads for this secret's value.
    public let envVar: String

    /// Creates a parsed secret. Normally produced by ``parseYAMLConfig(_:path:)``.
    public init(name: String, envVar: String) {
        self.name = name
        self.envVar = envVar
    }
}

/// One named environment in a sectioned Tightlip config.
public struct ParsedSection: Equatable, Sendable {
    /// The section (environment) name as written in the config, e.g. `staging`.
    public let name: String

    /// The secrets declared inside this section, in source order.
    public let secrets: [ParsedSecret]

    /// Creates a parsed section. Normally produced by ``parseYAMLConfig(_:path:)``.
    public init(name: String, secrets: [ParsedSecret]) {
        self.name = name
        self.secrets = secrets
    }
}

/// The result of parsing a Tightlip YAML config file.
public enum ParsedConfig: Equatable, Sendable {
    /// Flat format: a simple list of property → env-var mappings.
    case flat([ParsedSecret])

    /// Sectioned format: named environments, each containing identical property sets.
    case sectioned([ParsedSection])
}

/// A parsed config plus the optional `envFile:` directive that may precede it.
public struct ParsedConfigFile: Equatable, Sendable {
    /// The secrets section of the config (flat or sectioned).
    public let secrets: ParsedConfig

    /// Raw path as written after `envFile:` at the top of the YAML, or nil if not declared.
    /// Tilde-expansion and relative-path resolution are the caller's responsibility.
    public let envFile: String?

    /// Creates a parsed config file. Normally produced by ``parseYAMLConfigFile(_:path:)``.
    public init(secrets: ParsedConfig, envFile: String? = nil) {
        self.secrets = secrets
        self.envFile = envFile
    }
}

/// An error surfaced by the Tightlip tool during config parsing or env-var resolution.
public enum ConfigError: Error, Equatable, Sendable {
    /// The config file did not match the accepted grammar.
    case parse(path: String, line: Int?, reason: String)

    /// A declared secret's environment variable was not set when the build tool ran.
    case missingEnvironmentVariable(envVar: String, property: String)

    /// The active environment could not be determined for a sectioned config.
    case indeterminateEnvironment(available: [String], reason: String)

    /// Formatted message matching the `error:` output the CLI emits to stderr.
    public var message: String {
        switch self {
        case .parse(let path, let line, let reason):
            if let line {
                return "\(path):\(line): \(reason)"
            }
            return "\(path): \(reason)"
        case .missingEnvironmentVariable(let envVar, let property):
            // One line per variable so each renders as its own issue in Xcode; the
            // tool prints the "set it in your shell / ~/.zshenv / CI" guidance once.
            return "environment variable \(envVar) must be set to generate \(property)"
        case .indeterminateEnvironment(let available, let reason):
            return """
                cannot determine environment: \(reason). \
                Available environments: \(available.joined(separator: ", ")). \
                Set TIGHTLIP_ENV to one of these values.
                """
        }
    }
}

/// Parses a Tightlip YAML config, returning either a flat or sectioned result.
///
/// The format is auto-detected from the first meaningful line:
/// - If it matches `identifier:` with no value, the file is **sectioned** (environments).
/// - Otherwise, it's the classic **flat** format.
///
/// If the config begins with an `envFile:` directive, that directive is consumed silently
/// and not reflected in the return value. Use ``parseYAMLConfigFile(_:path:)`` to obtain
/// the directive alongside the parsed body.
///
/// - Parameters:
///   - text: Full config file contents.
///   - path: Path of the config file, echoed in any thrown error.
/// - Returns: A ``ParsedConfig`` representing the file contents.
/// - Throws: ``ConfigError/parse(path:line:reason:)`` on any grammar violation.
public func parseYAMLConfig(_ text: String, path: String) throws(ConfigError) -> ParsedConfig {
    try parseYAMLConfigFile(text, path: path).secrets
}

/// Parses a Tightlip YAML config and any leading `envFile:` directive.
///
/// The `envFile:` directive, if present, must appear before any other non-blank/non-comment
/// line. Its value is everything after `envFile:`, trimmed; it may contain path characters
/// (`/`, `~`, `.`, `-`, etc.) that are not valid identifiers.
///
/// - Parameters:
///   - text: Full config file contents.
///   - path: Path of the config file, echoed in any thrown error.
/// - Returns: A ``ParsedConfigFile`` wrapping the parsed config and optional envFile path.
/// - Throws: ``ConfigError/parse(path:line:reason:)`` on any grammar violation.
public func parseYAMLConfigFile(_ text: String, path: String) throws(ConfigError) -> ParsedConfigFile {
    let lines = text.components(separatedBy: "\n")
    let normalized = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }

    let (envFile, body) = try extractEnvFileDirective(normalized, path: path)

    let firstMeaningful = body.first {
        let s = $0.trimmingCharacters(in: .whitespaces)
        return !s.isEmpty && !s.hasPrefix("#")
    }

    guard let first = firstMeaningful else {
        throw .parse(path: path, line: nil, reason: "no secrets declared")
    }

    let secrets: ParsedConfig
    if isSectionHeader(first) {
        secrets = .sectioned(try parseSectioned(body, path: path))
    } else {
        secrets = .flat(try parseFlat(body, path: path))
    }
    return ParsedConfigFile(secrets: secrets, envFile: envFile)
}

/// Captures an optional leading `envFile:` directive from a normalized line array.
///
/// Recognizes `envFile:` only when it is the first non-blank, non-comment line at column 1.
/// Returns the directive value (raw, trimmed) and a copy of `lines` with the directive
/// line replaced by a blank line so downstream error line numbers stay correct.
///
/// The Lipservice plugin duplicates this recognition rule (plugins can't link this
/// target) to declare the env file as a build input — keep
/// `Plugins/Lipservice/Lipservice.swift` (`envFileInput`) in sync when changing it.
private func extractEnvFileDirective(
    _ lines: [String],
    path: String
) throws(ConfigError) -> (envFile: String?, body: [String]) {
    var output = lines
    for (idx, rawLine) in lines.enumerated() {
        let lineNumber = idx + 1
        let stripped = rawLine.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty || stripped.hasPrefix("#") { continue }

        guard rawLine.first?.isWhitespace == false else { return (nil, output) }

        let directive = "envFile:"
        guard stripped.hasPrefix(directive) else { return (nil, output) }

        let value = String(stripped.dropFirst(directive.count)).trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            throw .parse(path: path, line: lineNumber, reason: "envFile directive has no value")
        }
        if rawLine.contains("\t") {
            throw .parse(path: path, line: lineNumber, reason: "tab character not allowed; use spaces")
        }
        if value.contains("#") || value.contains(where: \.isWhitespace) {
            // A stray "# comment" silently becomes part of the path, fileExists fails,
            // and sourcing falls back to the process environment — reject it loudly.
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "envFile path must not contain spaces or '#' (inline comments are not supported)"
            )
        }
        if isIdentifier(value) {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: """
                    envFile value '\(value)' is ambiguous with a secret mapping; \
                    for a relative path, write './\(value)'
                    """
            )
        }
        output[idx] = ""
        return (value, output)
    }
    return (nil, output)
}

private func isSectionHeader(_ line: String) -> Bool {
    guard let first = line.first, !first.isWhitespace else { return false }
    let stripped = line.trimmingCharacters(in: .init(charactersIn: " "))
    guard stripped.hasSuffix(":") else { return false }
    let name = String(stripped.dropLast())
    return isIdentifier(name) && !stripped.contains(" ")
}

private func parseFlat(_ lines: [String], path: String) throws(ConfigError) -> [ParsedSecret] {
    var seen: [String: Int] = [:]
    var result: [ParsedSecret] = []

    for (idx, rawLine) in lines.enumerated() {
        let lineNumber = idx + 1
        let stripped = rawLine.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty || stripped.hasPrefix("#") { continue }

        if rawLine.first?.isWhitespace == true {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "unexpected indentation; every line must start at column 1"
            )
        }
        if rawLine.contains("\t") {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "tab character not allowed; use spaces"
            )
        }

        guard let (name, envVar) = splitMapping(stripped) else {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "expected '<name>: <ENV_VAR>', got '\(stripped)'"
            )
        }
        if let reason = reservedNameReason(name) {
            throw .parse(path: path, line: lineNumber, reason: reason)
        }
        if let prior = seen[name] {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "duplicate key '\(name)' (first defined on line \(prior))"
            )
        }
        seen[name] = lineNumber
        result.append(ParsedSecret(name: name, envVar: envVar))
    }

    if result.isEmpty {
        throw .parse(path: path, line: nil, reason: "no secrets declared")
    }
    return result
}

private func parseSectioned(
    _ lines: [String],
    path: String
) throws(ConfigError) -> [ParsedSection] {
    var sections: [ParsedSection] = []
    var currentSection: String?
    var currentSecrets: [ParsedSecret] = []
    var seen: [String: Int] = [:]
    var sectionNames: Set<String> = []

    for (idx, rawLine) in lines.enumerated() {
        let lineNumber = idx + 1
        let stripped = rawLine.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty || stripped.hasPrefix("#") { continue }

        if rawLine.contains("\t") {
            throw .parse(path: path, line: lineNumber, reason: "tab character not allowed; use spaces")
        }

        if rawLine.first.map({ !$0.isWhitespace }) ?? false {
            // Top-level line — must be a section header.
            guard isSectionHeader(rawLine) else {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "expected section header '<env>:', got '\(stripped)'"
                )
            }
            if let prev = currentSection {
                if currentSecrets.isEmpty {
                    throw .parse(path: path, line: lineNumber, reason: "section '\(prev)' has no secrets")
                }
                sections.append(ParsedSection(name: prev, secrets: currentSecrets))
            }
            let name = String(stripped.dropLast())
            if sectionNames.contains(name) {
                throw .parse(path: path, line: lineNumber, reason: "duplicate section '\(name)'")
            }
            sectionNames.insert(name)
            currentSection = name
            currentSecrets = []
            seen = [:]
        } else {
            // Indented line — must be inside a section.
            guard currentSection != nil else {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "unexpected indentation; every line must start at column 1"
                )
            }
            guard
                rawLine.hasPrefix("  ")
                    && (rawLine.count < 3 || rawLine[rawLine.index(rawLine.startIndex, offsetBy: 2)] != " ")
            else {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "use exactly 2-space indent inside environment sections"
                )
            }
            guard let (name, envVar) = splitMapping(stripped) else {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "expected '  <name>: <ENV_VAR>', got '\(rawLine)'"
                )
            }
            if let reason = reservedNameReason(name) {
                throw .parse(path: path, line: lineNumber, reason: reason)
            }
            if let prior = seen[name] {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "duplicate key '\(name)' (first defined on line \(prior))"
                )
            }
            seen[name] = lineNumber
            currentSecrets.append(ParsedSecret(name: name, envVar: envVar))
        }
    }

    if let prev = currentSection {
        if currentSecrets.isEmpty {
            throw .parse(path: path, line: nil, reason: "section '\(prev)' has no secrets")
        }
        sections.append(ParsedSection(name: prev, secrets: currentSecrets))
    }

    if sections.isEmpty {
        throw .parse(path: path, line: nil, reason: "no secrets declared")
    }

    // Validate all sections have the same property names.
    let referenceKeys = Set(sections[0].secrets.map(\.name))
    for section in sections.dropFirst() {
        let keys = Set(section.secrets.map(\.name))
        if keys != referenceKeys {
            let missing = referenceKeys.subtracting(keys).sorted()
            let extra = keys.subtracting(referenceKeys).sorted()
            var parts: [String] = []
            if !missing.isEmpty { parts.append("missing \(missing.joined(separator: ", "))") }
            if !extra.isEmpty { parts.append("unexpected \(extra.joined(separator: ", "))") }
            throw .parse(
                path: path,
                line: nil,
                reason: "section '\(section.name)' differs from '\(sections[0].name)': \(parts.joined(separator: "; "))"
            )
        }
    }

    return sections
}

/// Determines which environment section to use based on process environment.
///
/// Resolution order:
/// 1. `TIGHTLIP_ENV` — explicit override, used directly.
/// 2. `CONFIGURATION` (set by Xcode) — inferred when exactly two sections exist and one is
///    named `prod` or `production`. `Release` maps to that section; `Debug` (or an unset
///    `CONFIGURATION`) maps to the other. Any other configuration name is an error —
///    guessing non-production for a custom Release-like configuration (e.g. "AppStore")
///    would silently ship the wrong keys.
/// 3. Error if neither mechanism resolves.
public func resolveEnvironment(
    sections: [ParsedSection],
    environment: [String: String]
) throws(ConfigError) -> String {
    let sectionNames = sections.map(\.name)

    if let explicit = environment["TIGHTLIP_ENV"], !explicit.isEmpty {
        guard sectionNames.contains(explicit) else {
            throw .indeterminateEnvironment(
                available: sectionNames,
                reason: "TIGHTLIP_ENV='\(explicit)' does not match any section"
            )
        }
        return explicit
    }

    if sectionNames.count == 2 {
        // Inference needs exactly one prod-named section; with both `prod` and
        // `production` present there is no "other" section to map Debug onto.
        let prodNames = sectionNames.filter { $0 == "prod" || $0 == "production" }
        if prodNames.count == 1, let prodName = prodNames.first,
            let otherName = sectionNames.first(where: { $0 != prodName })
        {
            let configuration = environment["CONFIGURATION"] ?? ""
            switch configuration.lowercased() {
            case "release":
                return prodName
            case "debug", "":
                return otherName
            default:
                throw .indeterminateEnvironment(
                    available: sectionNames,
                    reason: """
                        CONFIGURATION='\(configuration)' is neither 'Debug' nor 'Release', \
                        so automatic inference refuses to guess
                        """
                )
            }
        }
    }

    throw .indeterminateEnvironment(
        available: sectionNames,
        reason: "TIGHTLIP_ENV is not set and automatic inference is not possible"
    )
}

private func splitMapping(_ s: String) -> (String, String)? {
    guard let colonIdx = s.firstIndex(of: ":") else { return nil }
    let name = String(s[s.startIndex..<colonIdx])
    guard isIdentifier(name) else { return nil }

    var rest = s[s.index(after: colonIdx)...]
    while rest.first == " " { rest = rest.dropFirst() }
    while rest.last == " " { rest = rest.dropLast() }

    let envVar = String(rest)
    guard isIdentifier(envVar) else { return nil }
    return (name, envVar)
}

/// Swift reserved keywords that are invalid as unescaped member declaration names.
/// A secret named `class` would render as `static let class: String = ...`, which
/// fails to compile inside the generated file — reject it at parse time instead.
private let swiftKeywords: Set<String> = [
    // Declarations
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
    "import", "init", "inout", "internal", "let", "open", "operator", "private",
    "precedencegroup", "protocol", "public", "rethrows", "static", "struct",
    "subscript", "typealias", "var",
    // Statements
    "break", "case", "catch", "continue", "default", "defer", "do", "else",
    "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch",
    "throw", "where", "while",
    // Expressions and types
    "Any", "Self", "as", "false", "is", "nil", "self", "super", "throws", "true", "try",
]

/// Member names the generated `Secrets` enum already uses for its decode shim, plus
/// unqualified symbols the shim's body references. A property with one of these names
/// would shadow the symbol inside the enum and break compilation of the generated file
/// (qualifying the shim doesn't help: a member named `Foundation` shadows
/// `Foundation.Data` just the same).
private let generatedHelperNames: Set<String> = [
    "salt", "decode",
    "Data", "String", "UInt8", "UTF8", "fatalError",
]

/// Names Swift rejects as member declarations even though they lex as identifiers:
/// `Type` and `Protocol` collide with metatype syntax (`Secrets.Type`), and `_` binds
/// no variable.
private let restrictedMemberNames: Set<String> = ["Type", "Protocol", "_"]

/// Returns a parse-error reason if `name` cannot be emitted as a property on the
/// generated enum, or nil if the name is usable.
private func reservedNameReason(_ name: String) -> String? {
    if name == "envFile" {
        // Allowed only in directive position (the first meaningful line); as a
        // property name anywhere else it would make the config ambiguous.
        return "'envFile' is reserved for the envFile directive and cannot be used as a secret name"
    }
    if swiftKeywords.contains(name) {
        return "'\(name)' is a Swift keyword and cannot be used as a secret name"
    }
    if restrictedMemberNames.contains(name) {
        return "'\(name)' cannot be declared as a member name in Swift and cannot be used as a secret name"
    }
    if generatedHelperNames.contains(name) {
        return "'\(name)' is reserved by the generated Secrets enum and cannot be used as a secret name"
    }
    return nil
}

private func isIdentifier(_ s: String) -> Bool {
    guard let first = s.first else { return false }
    guard first.isASCII, first.isLetter || first == "_" else { return false }
    for c in s.dropFirst() {
        guard c.isASCII, c.isLetter || c.isNumber || c == "_" else { return false }
    }
    return true
}

/// Resolves a single parsed secret against an environment dictionary.
///
/// An env var set to the empty string counts as set — only an absent key triggers an
/// error.
///
/// - Parameters:
///   - parsed: The parsed secret to resolve.
///   - environment: Environment variables to look up in.
/// - Returns: The secret's Swift property name paired with its resolved string value.
/// - Throws: ``ConfigError/missingEnvironmentVariable(envVar:property:)`` when
///   `parsed.envVar` is not a key in `environment`.
public func resolveSecret(
    _ parsed: ParsedSecret,
    environment: [String: String]
) throws(ConfigError) -> (name: String, value: String) {
    guard let value = environment[parsed.envVar] else {
        throw .missingEnvironmentVariable(
            envVar: parsed.envVar,
            property: "Secrets.\(parsed.name)"
        )
    }
    return (name: parsed.name, value: value)
}

/// Builds the typo-hunting note emitted when a declared env var is missing.
///
/// Lists every variable in `environment` that shares the missing variable's
/// leading underscore-delimited prefix (e.g. `ACME_` for `ACME_API_KEY`), so a
/// near-miss name is visible right next to the error. Pass the same merged
/// environment used for resolution — the process env alone would miss
/// variables that came from the sourced env file.
///
/// - Parameters:
///   - envVar: The environment variable that failed to resolve.
///   - environment: The environment the resolution actually consulted.
/// - Returns: A single-line diagnostic without a `note:` prefix or newline.
public func missingEnvVarDiagnostic(envVar: String, environment: [String: String]) -> String {
    let prefix = envVar.split(separator: "_").first.map(String.init) ?? envVar
    let visible = environment.keys
        .filter { $0.hasPrefix("\(prefix)_") }
        .sorted()
    return "\(visible.count) env var(s) with prefix '\(prefix)_' visible to the build: "
        + "[\(visible.joined(separator: ", "))]; total env count = \(environment.count)"
}

/// Renders the generated `nonisolated enum Secrets { ... }` Swift source.
///
/// Values are XOR-obfuscated with a 32-byte salt deterministically derived from the
/// resolved name/value pairs, then base64-encoded. The generated enum exposes plaintext
/// `String` properties via a private decode shim; obfuscation keeps the literal bytes out
/// of the compiled binary's strings table.
///
/// Properties are emitted in alphabetical order. Same inputs produce byte-identical output
/// (deterministic salt), so unchanged secrets do not trigger downstream recompiles.
///
/// - Parameters:
///   - resolved: Name/value pairs.
///   - environment: If non-nil, annotates the header with the active environment name.
/// - Returns: Complete Swift source text, terminated with a trailing newline.
public func renderSecretsEnum(
    _ resolved: [(name: String, value: String)],
    environment: String? = nil
) -> String {
    let sorted = resolved.sorted { $0.name < $1.name }
    let salt = deriveSalt(for: sorted)

    let properties =
        sorted
        .map { "    static let \($0.name): String = Self.decode(\"\(obfuscate($0.value, salt: salt))\")" }
        .joined(separator: "\n")

    let saltLiteral = salt.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
    let envLine = environment.map { "\n// Environment: \($0)" } ?? ""

    return """
        // Auto-generated by Tightlip. Do not edit.
        // Regenerated from environment variables when Secrets.yml or the env file changes.\(envLine)
        import Foundation

        nonisolated enum Secrets {
        \(properties)

            private static let salt: [UInt8] = [\(saltLiteral)]
            private static func decode(_ encoded: String) -> String {
                guard let data = Data(base64Encoded: encoded) else {
                    fatalError("Tightlip: corrupt secret payload; clean and rebuild")
                }
                var bytes = [UInt8](data)
                for i in bytes.indices { bytes[i] ^= salt[i % salt.count] }
                return String(decoding: bytes, as: UTF8.self)
            }
        }

        """
}

/// Derives a deterministic 32-byte salt from sorted name/value pairs.
///
/// Determinism is intentional: same inputs → byte-identical generated file → no spurious
/// downstream recompiles when secrets are unchanged.
private func deriveSalt(for resolved: [(name: String, value: String)]) -> [UInt8] {
    var hasher = SHA256()
    for (name, value) in resolved {
        hasher.update(data: Data(name.utf8))
        hasher.update(data: Data([0x1F]))
        hasher.update(data: Data(value.utf8))
        hasher.update(data: Data([0x1E]))
    }
    return Array(hasher.finalize())
}

/// XOR-encodes `value` against `salt` (cycling) and returns the base64 string.
private func obfuscate(_ value: String, salt: [UInt8]) -> String {
    var bytes = Array(value.utf8)
    for i in bytes.indices { bytes[i] ^= salt[i % salt.count] }
    return Data(bytes).base64EncodedString()
}

// MARK: - Shell-sourced environment

/// Namespace for Tightlip defaults to avoid polluting the importer's global scope.
public enum TightlipDefaults {
    /// envFile path used when the YAML config does not specify one.
    public static let envFilePath = "~/.zshenv"
}

#if os(macOS)
private let envFileHelperVar = "TIGHTLIP_ENV_FILE"
#endif

/// Sentinel entry the capture subshell appends after `env -0` carrying `source`'s exit
/// status. Its presence proves the dump ran to completion; its value distinguishes a
/// clean source from one that aborted partway.
private let sourceStatusSentinel = "TIGHTLIP_SOURCE_STATUS"

/// Expands a leading `~` to the user's home directory and resolves relative paths
/// against `configDir`. Paths that begin with `/` pass through unchanged.
///
/// The Lipservice plugin duplicates these resolution cases (see `envFileInput` in
/// `Plugins/Lipservice/Lipservice.swift`) — keep both in sync when changing them.
public func resolveEnvFilePath(
    _ rawPath: String,
    configDir: URL,
    homeDirectory: URL
) -> URL {
    if rawPath.hasPrefix("~/") {
        return homeDirectory.appendingPathComponent(String(rawPath.dropFirst(2)))
    }
    if rawPath == "~" {
        return homeDirectory
    }
    if rawPath.hasPrefix("/") {
        return URL(fileURLWithPath: rawPath)
    }
    return configDir.appendingPathComponent(rawPath)
}

/// Sources `envFile` in a clean zsh subshell, captures the resulting environment, and
/// layers `processEnvironment` on top per-key so process-level vars (CI overrides) win.
///
/// Behavior:
/// - If `envFile` does not exist on disk, returns `processEnvironment` unchanged (silent).
/// - If the subshell fails, times out, exits before dumping, or emits malformed output,
///   emits a single note and returns `processEnvironment` unchanged.
/// - If `source` aborts partway (e.g. a syntax error mid-file) but the dump still runs,
///   emits a note and returns the merged dict — exports above the failing line are
///   visible, exports below it are not.
/// - On success, returns the merged dict: sourced env, then `processEnvironment` overlaid.
///
/// - Parameters:
///   - envFile: Absolute path to a shell-sourceable file (e.g. `~/.zshenv` expanded).
///   - processEnvironment: The current process's environment, used as the per-key override.
///   - timeout: Max seconds to wait for the subshell. Defaults to 5.
///   - onNote: Receives diagnostic notes. Defaults to writing `note: …` lines to stderr.
/// - Returns: The merged environment dictionary.
public func captureShellEnvironment(
    envFile: URL,
    processEnvironment: [String: String],
    timeout: TimeInterval = 5,
    onNote: ((String) -> Void)? = nil
) -> [String: String] {
    #if os(macOS)
    guard FileManager.default.fileExists(atPath: envFile.path) else {
        return processEnvironment
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    // The sentinel printf runs after `env -0`, so a complete dump always ends with a
    // NUL-terminated TIGHTLIP_SOURCE_STATUS entry carrying `source`'s exit status. An
    // `exit` inside the env file kills the subshell before the dump — detectable as a
    // missing sentinel — and a mid-file syntax error surfaces as a non-zero status.
    process.arguments = [
        "-f",
        "-c",
        "source \"$\(envFileHelperVar)\" >/dev/null 2>&1; rc=$?; /usr/bin/env -0; "
            + "printf '\(sourceStatusSentinel)=%d\\0' \"$rc\"",
    ]
    var childEnv = processEnvironment
    childEnv[envFileHelperVar] = envFile.path
    process.environment = childEnv

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    // Drain the pipe asynchronously so no code path ever blocks on a read: the
    // kernel blocks `env -0` once output exceeds the pipe buffer, and a stuck
    // subshell would block a synchronous reader right back.
    let buffer = PipeBuffer()
    let sawEOF = DispatchSemaphore(value: 0)
    let readHandle = outputPipe.fileHandleForReading
    readHandle.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            sawEOF.signal()
        } else {
            buffer.append(data)
        }
    }

    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }

    do {
        try process.run()
    } catch {
        readHandle.readabilityHandler = nil
        return fallbackToProcessEnvironment(
            reason: "could not spawn /bin/zsh to source \(envFile.path): \(error)",
            processEnvironment: processEnvironment,
            onNote: onNote
        )
    }

    guard exited.wait(timeout: .now() + timeout) == .success else {
        // SIGTERM first so zsh can clean up its children; escalate to SIGKILL
        // for subshells whose env file traps TERM.
        process.terminate()
        if exited.wait(timeout: .now() + 0.5) != .success {
            kill(process.processIdentifier, SIGKILL)
        }
        readHandle.readabilityHandler = nil
        return fallbackToProcessEnvironment(
            reason: "sourcing \(envFile.path) timed out after \(timeout)s",
            processEnvironment: processEnvironment,
            onNote: onNote
        )
    }

    // The subshell has exited, so `env -0` finished writing. Wait briefly for
    // EOF to confirm the drain is complete; if some leftover child of the env
    // file holds the write end open, the buffered bytes are already all there
    // is to read.
    _ = sawEOF.wait(timeout: .now() + 0.25)
    readHandle.readabilityHandler = nil

    if process.terminationStatus != 0 {
        return fallbackToProcessEnvironment(
            reason: "sourcing \(envFile.path) exited \(process.terminationStatus)",
            processEnvironment: processEnvironment,
            onNote: onNote
        )
    }

    // Every complete entry — including the trailing sentinel — is NUL-terminated, so
    // bytes after the last NUL can only be a truncated fragment. Dropping them turns
    // a would-be corrupted value into a missing key (a loud error downstream).
    var outputData = buffer.data
    if let lastNul = outputData.lastIndex(of: 0x00) {
        outputData = outputData[...lastNul]
    } else {
        outputData = Data()
    }

    var sourced: [String: String] = [:]
    for part in outputData.split(separator: 0x00, omittingEmptySubsequences: true) {
        let entry = String(decoding: part, as: UTF8.self)
        guard let equalsIdx = entry.firstIndex(of: "=") else { continue }
        let key = String(entry[entry.startIndex..<equalsIdx])
        let value = String(entry[entry.index(after: equalsIdx)...])
        sourced[key] = value
    }

    guard let sourceStatus = sourced[sourceStatusSentinel] else {
        // `env -0` always dumps at least the inherited helper var, so an absent
        // sentinel means the subshell never reached the dump — an `exit` inside
        // the env file is the common cause.
        return fallbackToProcessEnvironment(
            reason: "sourcing \(envFile.path) did not complete (does it call exit?)",
            processEnvironment: processEnvironment,
            onNote: onNote
        )
    }
    sourced[sourceStatusSentinel] = nil

    if sourceStatus != "0" {
        // Note-only, not fallback: exports above the failing line are valid, and a
        // file whose last statement is a false conditional also reports non-zero.
        emitNote(
            "sourcing \(envFile.path) reported exit status \(sourceStatus); "
                + "the captured environment may be partial",
            onNote: onNote
        )
    }

    sourced[envFileHelperVar] = nil
    for (key, value) in processEnvironment {
        sourced[key] = value
    }
    return sourced
    #else
    // The build tool only ever runs on the macOS host; this branch exists solely so the
    // sources compile when Xcode builds the plugin tool for a non-macOS destination (a
    // long-standing Xcode behavior). It is never executed.
    return processEnvironment
    #endif
}

#if os(macOS)
private func emitNote(_ message: String, onNote: ((String) -> Void)?) {
    if let onNote {
        onNote(message)
    } else {
        FileHandle.standardError.write(Data("note: \(message)\n".utf8))
    }
}

private func fallbackToProcessEnvironment(
    reason: String,
    processEnvironment: [String: String],
    onNote: ((String) -> Void)?
) -> [String: String] {
    emitNote("\(reason); using process environment only", onNote: onNote)
    return processEnvironment
}

private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
#endif
