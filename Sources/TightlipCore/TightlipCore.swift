import CryptoKit
import Foundation

/// A single secret declared in a Tightlip YAML config.
public struct ParsedSecret: Equatable, Sendable {
    /// The Swift property name emitted on the generated `Secrets` enum.
    public let name: String

    /// The environment variable the build tool reads for this secret's value, without
    /// the `?` marker.
    public let envVar: String

    /// Whether the variable may be set to the empty string, written as a `?` after its
    /// name (`apiKey: APP_KEY?`). An unset variable is an error either way.
    public let allowsEmpty: Bool

    /// Creates a parsed secret. Normally produced by ``parseYAMLConfig(_:path:)``.
    public init(name: String, envVar: String, allowsEmpty: Bool = false) {
        self.name = name
        self.envVar = envVar
        self.allowsEmpty = allowsEmpty
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

/// The access level of the generated `Secrets` enum and its properties, set by the
/// `access:` directive.
public enum AccessLevel: String, Equatable, Sendable {
    /// Visible only inside the target that generates it. The default.
    case `internal`

    /// Visible to other targets in the same SwiftPM package.
    case `package`

    /// Visible to any module that imports the target.
    case `public`
}

/// A parsed config plus the optional `envFile:` and `access:` directives that may
/// precede it.
public struct ParsedConfigFile: Equatable, Sendable {
    /// The secrets section of the config (flat or sectioned).
    public let secrets: ParsedConfig

    /// Raw path as written after `envFile:` at the top of the YAML, or nil if not declared.
    /// Tilde-expansion and relative-path resolution are the caller's responsibility.
    public let envFile: String?

    /// The level declared by `access:` at the top of the YAML, or ``AccessLevel/internal``
    /// if not declared.
    public let access: AccessLevel

    /// Creates a parsed config file. Normally produced by ``parseYAMLConfigFile(_:path:)``.
    public init(secrets: ParsedConfig, envFile: String? = nil, access: AccessLevel = .internal) {
        self.secrets = secrets
        self.envFile = envFile
        self.access = access
    }
}

/// An error surfaced by the Tightlip tool during config parsing or env-var resolution.
public enum ConfigError: Error, Equatable, Sendable {
    /// The config file did not match the accepted grammar.
    case parse(path: String, line: Int?, reason: String)

    /// A declared secret's environment variable was not set when the build tool ran.
    case missingEnvironmentVariable(envVar: String, property: String)

    /// A declared secret's environment variable was set to the empty string, and its
    /// config line has no `?` marker allowing that.
    case emptyEnvironmentVariable(envVar: String, property: String)

    /// The active environment could not be determined for a sectioned config.
    case indeterminateEnvironment(available: [String], reason: String)

    /// Human-readable description of the error, without a severity prefix.
    public var message: String {
        switch self {
        case .parse(let path, let line, let reason):
            return "\(Self.location(path: path, line: line)): \(reason)"
        case .missingEnvironmentVariable(let envVar, let property):
            // One line per variable so each renders as its own issue in Xcode; the
            // tool prints the "set it in your shell / ~/.zshenv / CI" guidance once.
            return "environment variable \(envVar) must be set to generate \(property)"
        case .emptyEnvironmentVariable(let envVar, let property):
            return "environment variable \(envVar) is set but empty; \(property) needs a value"
        case .indeterminateEnvironment(let available, let reason):
            return """
                cannot determine environment: \(reason). \
                Available environments: \(available.joined(separator: ", ")). \
                Set TIGHTLIP_ENV to one of these values.
                """
        }
    }

    /// The line the build tool prints to stderr for this error, without a trailing newline.
    ///
    /// Parse errors use the `path:line: error: reason` form, which Xcode attributes to the
    /// file and line (a clickable issue); `error: path:line: reason` would render as
    /// unattributed text.
    public var diagnostic: String {
        switch self {
        case .parse(let path, let line, let reason):
            return "\(Self.location(path: path, line: line)): error: \(reason)"
        case .missingEnvironmentVariable, .emptyEnvironmentVariable, .indeterminateEnvironment:
            return "error: \(message)"
        }
    }

    private static func location(path: String, line: Int?) -> String {
        line.map { "\(path):\($0)" } ?? path
    }
}

/// Parses a Tightlip YAML config, returning either a flat or sectioned result.
///
/// The format is auto-detected from the first meaningful line after the header directives:
/// - If it matches `identifier:` with no value, the file is **sectioned** (environments).
/// - Otherwise, it's the classic **flat** format.
///
/// If the config begins with `envFile:` or `access:` directives, they are consumed
/// silently and not reflected in the return value. Use ``parseYAMLConfigFile(_:path:)``
/// to obtain the directives alongside the parsed body.
///
/// - Parameters:
///   - text: Full config file contents.
///   - path: Path of the config file, echoed in any thrown error.
/// - Returns: A ``ParsedConfig`` representing the file contents.
/// - Throws: ``ConfigError/parse(path:line:reason:)`` on any grammar violation.
public func parseYAMLConfig(_ text: String, path: String) throws(ConfigError) -> ParsedConfig {
    try parseYAMLConfigFile(text, path: path).secrets
}

/// Parses a Tightlip YAML config and any leading `envFile:` and `access:` directives.
///
/// The directives form the config's header: each may appear at most once, in either
/// order, at column 1 before any section header or mapping. The `envFile:` value is
/// everything after `envFile:`, trimmed; it may contain path characters (`/`, `~`, `.`,
/// `-`, etc.) that are not valid identifiers. The `access:` value must be exactly
/// `internal`, `package`, or `public`.
///
/// - Parameters:
///   - text: Full config file contents.
///   - path: Path of the config file, echoed in any thrown error.
/// - Returns: A ``ParsedConfigFile`` wrapping the parsed config, the optional envFile
///   path, and the access level.
/// - Throws: ``ConfigError/parse(path:line:reason:)`` on any grammar violation.
public func parseYAMLConfigFile(_ text: String, path: String) throws(ConfigError) -> ParsedConfigFile {
    let lines = text.components(separatedBy: "\n")
    let normalized = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }

    for (idx, line) in normalized.enumerated() {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty || stripped.hasPrefix("#") { continue }
        if let reason = invisibleCharacterReason(in: line) {
            throw .parse(path: path, line: idx + 1, reason: reason)
        }
    }

    let (envFile, access, body) = try extractHeaderDirectives(normalized, path: path)

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
    return ParsedConfigFile(secrets: secrets, envFile: envFile, access: access)
}

/// The directives a config may open with, before any section header or mapping.
private enum HeaderDirective: String, CaseIterable {
    case envFile
    case access

    var prefix: String { "\(rawValue):" }
}

/// Captures the optional leading `envFile:` and `access:` directives from a normalized
/// line array.
///
/// The header is the run of column-1 directive lines at the top of the file, with
/// blank lines and comments allowed between them. Each directive may appear once, in
/// either order; the first line that isn't a directive ends the header. Returns the
/// directive values and a copy of `lines` with each directive line replaced by a blank
/// line so downstream error line numbers stay correct.
///
/// The Lipservice plugin duplicates this recognition rule (plugins can't link this
/// target) to declare the env file as a build input and to keep directive values out of
/// the forwarded environment — keep `envFileInput` and `forwardedNames` in
/// `Plugins/Lipservice/Lipservice.swift` in sync when changing it.
private func extractHeaderDirectives(
    _ lines: [String],
    path: String
) throws(ConfigError) -> (envFile: String?, access: AccessLevel, body: [String]) {
    var output = lines
    var envFile: String?
    var access: AccessLevel = .internal
    var seen: [HeaderDirective: Int] = [:]
    for (idx, rawLine) in lines.enumerated() {
        let lineNumber = idx + 1
        let stripped = rawLine.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty || stripped.hasPrefix("#") { continue }

        guard rawLine.first?.isWhitespace == false,
            let directive = HeaderDirective.allCases.first(where: { stripped.hasPrefix($0.prefix) })
        else { break }

        if let prior = seen[directive] {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "duplicate \(directive.rawValue) directive (first defined on line \(prior))"
            )
        }
        seen[directive] = lineNumber

        let value = String(stripped.dropFirst(directive.prefix.count)).trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            throw .parse(path: path, line: lineNumber, reason: "\(directive.rawValue) directive has no value")
        }
        if rawLine.contains("\t") {
            throw .parse(path: path, line: lineNumber, reason: "tab character not allowed; use spaces")
        }
        switch directive {
        case .envFile:
            if let reason = envFilePathReason(value) {
                throw .parse(path: path, line: lineNumber, reason: reason)
            }
            envFile = value
        case .access:
            guard let level = AccessLevel(rawValue: value) else {
                // `access: NAME` also reads as a pre-2.0 mapping for a secret named `access`.
                let hint =
                    parseEnvVarReference(value[...]) != nil
                    ? "; for a secret named 'access', note that 'access' is reserved as a directive; rename the secret"
                    : ""
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "access must be internal, package, or public; got '\(value)'\(hint)"
                )
            }
            access = level
        }
        output[idx] = ""
    }
    return (envFile, access, output)
}

/// Returns a parse-error reason if an `envFile:` value can't name the file it appears
/// to, or nil if the path is usable.
private func envFilePathReason(_ value: String) -> String? {
    if value.contains("#") || value.contains(where: \.isWhitespace) {
        // A stray "# comment" silently becomes part of the path, fileExists fails,
        // and sourcing falls back to the process environment — reject it loudly.
        return "envFile path must not contain spaces or '#' (inline comments are not supported)"
    }
    if value.contains(where: { "\"'$`".contains($0) }) {
        // Nothing here expands shell syntax, so `"./x.env"` or `$HOME/x.env` would
        // silently become a literal relative path that never exists.
        return "envFile path must be written bare; quotes, '$', and backticks are not expanded"
    }
    if value == "~" || value.hasSuffix("/") {
        // zsh's `source` of a directory succeeds and exports nothing, so this
        // would otherwise be a silent no-op.
        return "envFile must name a file, not a directory"
    }
    if value.hasPrefix("~"), !value.hasPrefix("~/") {
        return "only a leading '~/' is expanded in an envFile path; '~user' paths are not supported"
    }
    // `KEY?` reads as a mapping just as much as `KEY` does.
    if parseEnvVarReference(value[...]) != nil {
        return "envFile value '\(value)' is ambiguous with a secret mapping; for a relative path, write './\(value)'"
    }
    return nil
}

/// Returns a parse-error reason for the first character in `line` that is invisible or
/// renders like a plain space — a no-break space pasted from a chat app, a zero-width
/// space, a stray carriage return — or nil if there is none.
///
/// Without this, such a character fails an identifier check further down and the error
/// echoes a line that looks exactly like a valid one. Tabs are left to the grammar's
/// dedicated tab error.
private func invisibleCharacterReason(in line: String) -> String? {
    for (offset, character) in line.enumerated() where character != " " && character != "\t" {
        for scalar in character.unicodeScalars {
            let properties = scalar.properties
            let isInvisible =
                properties.isWhitespace
                || [.control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator]
                    .contains(properties.generalCategory)
            guard isInvisible else { continue }

            if scalar == "\r" {
                return "stray carriage return (U+000D) at column \(offset + 1); "
                    + "save the file with LF or CRLF line endings"
            }
            let name = properties.name.map { " \($0)" } ?? ""
            let fix = properties.isWhitespace ? "retype it as a plain space" : "delete it"
            return "invisible character \(String(format: "U+%04X", scalar.value))\(name) "
                + "at column \(offset + 1); \(fix)"
        }
    }
    return nil
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

        guard let secret = splitMapping(stripped) else {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "expected '<name>: <ENV_VAR>', got '\(stripped)'"
            )
        }
        if let reason = reservedNameReason(secret.name) {
            throw .parse(path: path, line: lineNumber, reason: reason)
        }
        if let prior = seen[secret.name] {
            throw .parse(
                path: path,
                line: lineNumber,
                reason: "duplicate key '\(secret.name)' (first defined on line \(prior))"
            )
        }
        seen[secret.name] = lineNumber
        result.append(secret)
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
    // Header line per section, so section-level errors point at the header.
    var headerLines: [String: Int] = [:]

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
                    throw .parse(path: path, line: headerLines[prev], reason: "section '\(prev)' has no secrets")
                }
                sections.append(ParsedSection(name: prev, secrets: currentSecrets))
            }
            let name = String(stripped.dropLast())
            if let prior = headerLines[name] {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "duplicate section '\(name)' (first defined on line \(prior))"
                )
            }
            headerLines[name] = lineNumber
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
            guard let secret = splitMapping(stripped) else {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "expected '  <name>: <ENV_VAR>', got '\(rawLine)'"
                )
            }
            if let reason = reservedNameReason(secret.name) {
                throw .parse(path: path, line: lineNumber, reason: reason)
            }
            if let prior = seen[secret.name] {
                throw .parse(
                    path: path,
                    line: lineNumber,
                    reason: "duplicate key '\(secret.name)' (first defined on line \(prior))"
                )
            }
            seen[secret.name] = lineNumber
            currentSecrets.append(secret)
        }
    }

    if let prev = currentSection {
        if currentSecrets.isEmpty {
            throw .parse(path: path, line: headerLines[prev], reason: "section '\(prev)' has no secrets")
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
                line: headerLines[section.name],
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

/// Splits a `name: ENV_VAR` or `name: ENV_VAR?` line into a secret, or returns nil if
/// the line doesn't have that shape. Name-level checks (reserved names, duplicates) are
/// the caller's.
private func splitMapping(_ s: String) -> ParsedSecret? {
    guard let colonIdx = s.firstIndex(of: ":") else { return nil }
    let name = String(s[s.startIndex..<colonIdx])
    guard isIdentifier(name) else { return nil }

    var rest = s[s.index(after: colonIdx)...]
    while rest.first == " " { rest = rest.dropFirst() }
    while rest.last == " " { rest = rest.dropLast() }

    guard let (envVar, allowsEmpty) = parseEnvVarReference(rest) else { return nil }
    return ParsedSecret(name: name, envVar: envVar, allowsEmpty: allowsEmpty)
}

/// Parses the right side of a mapping: an identifier, optionally followed by the `?`
/// marker that allows an empty value.
///
/// The Lipservice plugin duplicates this rule (`forwardedNames` in
/// `Plugins/Lipservice/Lipservice.swift`) to forward each variable — keep both in sync.
private func parseEnvVarReference(_ s: Substring) -> (envVar: String, allowsEmpty: Bool)? {
    let allowsEmpty = s.last == "?"
    let envVar = String(allowsEmpty ? s.dropLast() : s)
    return isIdentifier(envVar) ? (envVar, allowsEmpty) : nil
}

/// Swift reserved keywords that are invalid as unescaped member declaration names.
/// A secret named `class` would render as `static let class: String = ...`, which
/// fails to compile inside the generated file — reject it at parse time instead.
private let swiftKeywords: Set<String> = [
    // Declarations
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
    "import", "init", "inout", "internal", "let", "operator", "private",
    "precedencegroup", "protocol", "public", "rethrows", "static", "struct",
    "subscript", "typealias", "var",
    // Statements
    "break", "case", "catch", "continue", "default", "defer", "do", "else",
    "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch",
    "throw", "where", "while",
    // Expressions and types
    "Any", "Self", "as", "false", "is", "nil", "self", "super", "throws", "true", "try",
]

/// Names the generated `Secrets` enum reserves for itself. `salt` would collide with the
/// shim's stored property. `decode` technically compiles alongside `decode(_:)`, but is
/// reserved so a property and the shim never share a name. The shim spells every
/// library symbol module-qualified (`Foundation.Data`, `Swift.String`, …) so that
/// neither a member nor a consumer type named `Data` or `UTF8` can shadow it — which in
/// turn reserves the two module names, since a member named `Swift` would shadow the
/// qualifier itself.
private let generatedHelperNames: Set<String> = [
    "salt", "decode", "Swift", "Foundation",
]

/// Names Swift rejects as member declarations even though they lex as identifiers:
/// `Type` and `Protocol` collide with metatype syntax (`Secrets.Type`), and `_` binds
/// no variable.
private let restrictedMemberNames: Set<String> = ["Type", "Protocol", "_"]

/// Returns a parse-error reason if `name` cannot be emitted as a property on the
/// generated enum, or nil if the name is usable.
private func reservedNameReason(_ name: String) -> String? {
    if HeaderDirective(rawValue: name) != nil {
        // Allowed only in directive position (the header); as a property name anywhere
        // else it would make the config ambiguous.
        return "'\(name)' is reserved for the \(name) directive and cannot be used as a secret name"
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
/// An env var set to the empty string is an error unless the secret's config line marks
/// it with `?` (``ParsedSecret/allowsEmpty``).
///
/// - Parameters:
///   - parsed: The parsed secret to resolve.
///   - environment: Environment variables to look up in.
/// - Returns: The secret's Swift property name paired with its resolved string value.
/// - Throws: ``ConfigError/missingEnvironmentVariable(envVar:property:)`` when
///   `parsed.envVar` is not a key in `environment`, or
///   ``ConfigError/emptyEnvironmentVariable(envVar:property:)`` when its value is empty
///   and `parsed.allowsEmpty` is false.
public func resolveSecret(
    _ parsed: ParsedSecret,
    environment: [String: String]
) throws(ConfigError) -> (name: String, value: String) {
    let property = "Secrets.\(parsed.name)"
    guard let value = environment[parsed.envVar] else {
        throw .missingEnvironmentVariable(envVar: parsed.envVar, property: property)
    }
    if value.isEmpty, !parsed.allowsEmpty {
        throw .emptyEnvironmentVariable(envVar: parsed.envVar, property: property)
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
    // Leading underscores belong to the prefix: `_ACME_KEY` groups with `_ACME_*`.
    let leading = envVar.prefix(while: { $0 == "_" })
    let stem = envVar.dropFirst(leading.count).prefix(while: { $0 != "_" })
    let prefix = String(leading + stem)
    let visible = environment.keys
        .filter { $0.hasPrefix("\(prefix)_") }
        .sorted()
    return "\(visible.count) env var(s) with prefix '\(prefix)_' visible to the build: "
        + "[\(visible.joined(separator: ", "))]; total env count = \(environment.count)"
}

/// Renders the generated `nonisolated enum Secrets { ... }` Swift source.
///
/// `access` prefixes the enum and every property with its keyword; `salt` and `decode`
/// stay `private`. ``AccessLevel/internal`` writes no keyword, so its output matches a
/// config without an `access:` directive byte for byte.
///
/// Every name must be an identifier that the parser accepts as a secret name, and
/// `environment` must be an identifier; anything else traps rather than splicing
/// arbitrary text into Swift source.
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
///   - access: The access level of the enum and its properties.
/// - Returns: Complete Swift source text, terminated with a trailing newline.
public func renderSecretsEnum(
    _ resolved: [(name: String, value: String)],
    environment: String? = nil,
    access: AccessLevel = .internal
) -> String {
    let sorted = resolved.sorted { $0.name < $1.name }
    let salt = deriveSalt(for: sorted)

    for (name, _) in sorted {
        precondition(isIdentifier(name) && reservedNameReason(name) == nil, "invalid secret name '\(name)'")
    }
    precondition(environment.map(isIdentifier) ?? true, "invalid environment name")

    let keyword = access == .internal ? "" : "\(access.rawValue) "
    let properties =
        sorted
        .map { name, value in
            "    \(keyword)static let \(name): Swift.String = Self.decode(\"\(obfuscate(value, salt: salt))\")"
        }
        .joined(separator: "\n")

    let saltLiteral = salt.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
    let envLine = environment.map { "\n// Environment: \($0)" } ?? ""

    return """
        // Auto-generated by Tightlip. Do not edit.
        // Regenerated from environment variables when Secrets.yml or the env file changes.\(envLine)
        import Foundation

        \(keyword)nonisolated enum Secrets {
        \(properties)

            private static let salt: [Swift.UInt8] = [\(saltLiteral)]
            private static func decode(_ encoded: Swift.String) -> Swift.String {
                guard let data = Foundation.Data(base64Encoded: encoded) else {
                    Swift.fatalError("Tightlip: corrupt secret payload; clean and rebuild")
                }
                var bytes: [Swift.UInt8] = []
                bytes.reserveCapacity(data.count)
                var saltIndex = 0
                for byte in data {
                    bytes.append(byte ^ salt[saltIndex])
                    saltIndex = saltIndex == salt.count - 1 ? 0 : saltIndex + 1
                }
                return Swift.String(decoding: bytes, as: Swift.UTF8.self)
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

/// Expands a leading `~/` to the user's home directory and resolves relative paths
/// against `configDir`. Paths that begin with `/` pass through unchanged. The result is
/// standardized, so `a/../b` and doubled slashes don't produce distinct paths for one file.
///
/// The Lipservice plugin duplicates these resolution cases (see `envFileInput` in
/// `Plugins/Lipservice/Lipservice.swift`) — keep both in sync when changing them.
public func resolveEnvFilePath(
    _ rawPath: String,
    configDir: URL,
    homeDirectory: URL
) -> URL {
    let resolved: URL
    if rawPath.hasPrefix("~/") {
        resolved = homeDirectory.appendingPathComponent(String(rawPath.dropFirst(2)))
    } else if rawPath.hasPrefix("/") {
        resolved = URL(fileURLWithPath: rawPath)
    } else {
        resolved = configDir.appendingPathComponent(rawPath)
    }
    return resolved.standardizedFileURL
}

/// The result of ``captureShellEnvironment(envFile:processEnvironment:timeout:onNote:)``.
public struct CapturedEnvironment: Equatable, Sendable {
    /// The env file's exports with the process environment layered on top, per key.
    public let merged: [String: String]

    /// Keys the env file assigned a non-empty value that the process environment then
    /// overrode with a different one.
    ///
    /// The capture subshell inherits the process environment, so a key only lands here
    /// when the file itself reassigned it — typically because the terminal that launched
    /// the build still exports a value the file has since replaced. Empty file values are
    /// left out: a `$(…)` export that failed inside the build sandbox yields "", and the
    /// build environment overriding it is the desired outcome.
    public let overriddenKeys: Set<String>

    init(merged: [String: String], overriddenKeys: Set<String> = []) {
        self.merged = merged
        self.overriddenKeys = overriddenKeys
    }
}

/// Sources `envFile` in a clean zsh subshell, captures the resulting environment, and
/// layers `processEnvironment` on top per-key so process-level vars (CI overrides) win.
///
/// Behavior:
/// - If `envFile` does not exist on disk, returns `processEnvironment` unchanged (silent).
/// - If `envFile` is a directory or unreadable, or the subshell fails, times out, exits
///   before dumping, or emits malformed output, emits a single note and returns
///   `processEnvironment` unchanged.
/// - If `source` aborts partway (e.g. a syntax error mid-file) but the dump still runs,
///   emits a note and returns the merged dict — exports above the failing line are
///   visible, exports below it are not.
/// - A sourced value that is not valid UTF-8 is dropped with a note rather than decoded
///   lossily into a corrupted secret.
/// - On success, returns the merged dict: sourced env, then `processEnvironment` overlaid.
///
/// - Parameters:
///   - envFile: Absolute path to a shell-sourceable file (e.g. `~/.zshenv` expanded).
///   - processEnvironment: The build's environment: the subshell's starting environment
///     and the per-key override.
///   - timeout: Max seconds to wait for the subshell. Defaults to 5.
///   - onNote: Receives diagnostic notes, without a `note:` prefix. Defaults to discarding them.
/// - Returns: The merged environment and the keys whose file-assigned value was overridden.
public func captureShellEnvironment(
    envFile: URL,
    processEnvironment: [String: String],
    timeout: TimeInterval = 5,
    onNote: (String) -> Void = { _ in }
) -> CapturedEnvironment {
    #if os(macOS)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: envFile.path, isDirectory: &isDirectory) else {
        return CapturedEnvironment(merged: processEnvironment)
    }
    if isDirectory.boolValue || !FileManager.default.isReadableFile(atPath: envFile.path) {
        return fallbackToProcessEnvironment(
            reason: "\(envFile.path) is \(isDirectory.boolValue ? "a directory" : "not readable")",
            processEnvironment: processEnvironment,
            onNote: onNote
        )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    // The sentinel printf runs after `env -0`, so a complete dump always ends with a
    // NUL-terminated TIGHTLIP_SOURCE_STATUS entry carrying `source`'s exit status. An
    // `exit` inside the env file kills the subshell before the dump — detectable as a
    // missing sentinel — and a mid-file syntax error surfaces as a non-zero status.
    //
    // The pipe is parked on fd 3 and stdout/stderr point at /dev/null for everything
    // except the two dump commands, so nothing else the file leaves behind — a DEBUG,
    // ZERR, or EXIT trap, a zshexit hook, a background job — can write into the dump.
    // After `source`: `&& … ||` keeps a file-set ERR_EXIT from killing the shell,
    // `emulate -R zsh` resets options (ERR_EXIT/ERR_RETURN would otherwise abort the
    // remaining lines), `trap -` and the hook reset stop traps from running, and
    // dropping functions keeps them from shadowing `printf`. A failing `env` (e.g. an
    // environment past ARG_MAX) must not be masked by printf's status.
    process.arguments = [
        "-f",
        "-c",
        "exec 3>&1 >/dev/null 2>&1; "
            + "source \"$\(envFileHelperVar)\" </dev/null && __tightlip_rc=0 || __tightlip_rc=$?; "
            + "emulate -R zsh; trap -; zshexit_functions=(); unfunction -m '*'; "
            + "/usr/bin/env -0 >&3 || exit 125; "
            + "builtin printf '\(sourceStatusSentinel)=%d\\0' \"$__tightlip_rc\" >&3",
    ]
    var childEnv = processEnvironment
    childEnv[envFileHelperVar] = envFile.path
    // A file-exported sentinel would otherwise ride along in the dump.
    childEnv[sourceStatusSentinel] = nil
    process.environment = childEnv

    let outputPipe = Pipe()
    process.standardInput = FileHandle.nullDevice
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
        // SIGTERM first so zsh can clean up its children, then SIGKILL the whole
        // process group (Foundation starts zsh as its leader) whether or not zsh itself
        // exited: a TERM-ignoring child would otherwise outlive the build as an orphan.
        process.terminate()
        _ = exited.wait(timeout: .now() + 0.5)
        killpg(process.processIdentifier, SIGKILL)
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

    var sourced = parseEnvironmentEntries(outputData) { key in
        onNote("\(key) exported by \(envFile.path) is not valid UTF-8 and was ignored")
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
        onNote(
            "sourcing \(envFile.path) reported exit status \(sourceStatus); "
                + "the captured environment may be partial"
        )
    }

    sourced[envFileHelperVar] = nil
    var overridden: Set<String> = []
    for (key, value) in processEnvironment {
        if let fileValue = sourced[key], !fileValue.isEmpty, fileValue != value {
            overridden.insert(key)
        }
        sourced[key] = value
    }
    return CapturedEnvironment(merged: sourced, overriddenKeys: overridden)
    #else
    // The build tool only ever runs on the macOS host; this branch exists solely so the
    // sources compile when Xcode builds the plugin tool for a non-macOS destination (a
    // long-standing Xcode behavior). It is never executed.
    return CapturedEnvironment(merged: processEnvironment)
    #endif
}

/// Parses NUL-terminated `KEY=VALUE` entries — `env -0` output, or the environment file
/// the Lipservice plugin forwards. Entries without `=` are skipped; later duplicates win.
/// A value that is not valid UTF-8 is dropped and reported through `onInvalidUTF8`,
/// rather than decoded lossily into a corrupted secret.
private func parseEnvironmentEntries(
    _ data: Data,
    onInvalidUTF8: (String) -> Void
) -> [String: String] {
    var entries: [String: String] = [:]
    for part in data.split(separator: 0x00, omittingEmptySubsequences: true) {
        guard let equalsIdx = part.firstIndex(of: UInt8(ascii: "=")) else { continue }
        let key = String(decoding: part[..<equalsIdx], as: UTF8.self)
        guard let value = String(data: Data(part[part.index(after: equalsIdx)...]), encoding: .utf8) else {
            onInvalidUTF8(key)
            continue
        }
        entries[key] = value
    }
    return entries
}

#if os(macOS)
private func fallbackToProcessEnvironment(
    reason: String,
    processEnvironment: [String: String],
    onNote: (String) -> Void
) -> CapturedEnvironment {
    onNote("\(reason); using the build environment only")
    return CapturedEnvironment(merged: processEnvironment)
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

// MARK: - Build tool entry point

/// Runs one Lipservice generation: parse the config, assemble the build environment,
/// select the section, resolve every secret, and write the generated file.
///
/// Diagnostics go to `emit` as complete lines without trailing newlines, in the
/// `error:` / `warning:` / `note:` forms Xcode and SwiftPM surface in build logs.
///
/// - Parameters:
///   - configPath: Path to `Secrets.yml`.
///   - outputPath: Where to write the generated Swift file. Left untouched when the
///     rendered source matches what is already there, so a re-run with unchanged inputs
///     doesn't force the file to recompile.
///   - forwardedEnvironmentPath: A file of NUL-terminated `KEY=VALUE` entries the
///     Lipservice plugin copied from its own environment, or nil. SwiftPM's `swiftbuild`
///     backend runs build commands in a synthesized environment, so this file is the only
///     way the caller's variables reach the tool there.
///   - processEnvironment: The tool's own environment. Wins per key over forwarded entries.
///   - homeDirectory: Directory a leading `~/` in the env file path expands to.
///   - emit: Receives each diagnostic line.
/// - Returns: `true` on success; `false` once at least one `error:` line was emitted.
public func generateSecretsFile(
    configPath: String,
    outputPath: String,
    forwardedEnvironmentPath: String?,
    processEnvironment: [String: String],
    homeDirectory: URL,
    emit: (String) -> Void
) -> Bool {
    let configURL = URL(fileURLWithPath: configPath)
    let configText: String
    do {
        configText = try String(contentsOf: configURL, encoding: .utf8)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        emit(
            "error: Tightlip config missing at \(configPath). Create Secrets.yml there — "
                + "in a Swift package, the target's source directory; in an Xcode project, "
                + "a folder named after the target's display name, beside the .xcodeproj"
        )
        return false
    } catch let error as CocoaError
        where error.code == .fileReadInapplicableStringEncoding || error.code == .fileReadCorruptFile
    {
        let reason = "config is not valid UTF-8; save it with UTF-8 encoding"
        emit(ConfigError.parse(path: configPath, line: nil, reason: reason).diagnostic)
        return false
    } catch {
        emit("error: failed to read \(configPath): \(error.localizedDescription)")
        return false
    }

    let configFile: ParsedConfigFile
    do {
        configFile = try parseYAMLConfigFile(configText, path: configPath)
    } catch {
        emit(error.diagnostic)
        return false
    }

    var buildEnvironment: [String: String] = [:]
    if let forwardedEnvironmentPath {
        if let data = FileManager.default.contents(atPath: forwardedEnvironmentPath) {
            buildEnvironment = parseEnvironmentEntries(data) { key in
                emit("note: forwarded value of \(key) is not valid UTF-8 and was ignored")
            }
        } else {
            emit("note: forwarded environment missing at \(forwardedEnvironmentPath)")
        }
    }
    buildEnvironment.merge(processEnvironment) { _, process in process }

    let envFileURL = resolveEnvFilePath(
        configFile.envFile ?? TightlipDefaults.envFilePath,
        configDir: configURL.deletingLastPathComponent(),
        homeDirectory: homeDirectory
    )
    // An absent default ~/.zshenv is the normal CI case and stays silent, but an
    // explicitly declared envFile that doesn't resolve is a misconfiguration worth
    // pointing at before the missing-env-var errors it will cause.
    if configFile.envFile != nil, !FileManager.default.fileExists(atPath: envFileURL.path) {
        emit("note: declared envFile not found at \(envFileURL.path); using the build environment only")
    }
    let captured = captureShellEnvironment(
        envFile: envFileURL,
        processEnvironment: buildEnvironment,
        onNote: { emit("note: \($0)") }
    )
    let environment = captured.merged

    let secrets: [ParsedSecret]
    var envName: String?
    switch configFile.secrets {
    case .flat(let parsed):
        secrets = parsed
    case .sectioned(let sections):
        // Overriding the file's TIGHTLIP_ENV for one build is routine, and the selected
        // section is printed below anyway; a note is enough.
        if captured.overriddenKeys.contains("TIGHTLIP_ENV") {
            emit("note: TIGHTLIP_ENV from the build environment overrides the value \(envFileURL.path) exports")
        }
        let sectionName: String
        do {
            sectionName = try resolveEnvironment(sections: sections, environment: environment)
        } catch {
            emit(error.diagnostic)
            return false
        }
        guard let section = sections.first(where: { $0.name == sectionName }) else {
            emit("error: internal error: resolved environment '\(sectionName)' not found in sections")
            return false
        }
        envName = sectionName
        secrets = section.secrets
    }

    // Printed before resolution so a wrong-section pick is visible right above the
    // missing-variable errors it tends to cause.
    if let envName {
        emit("note: using environment '\(envName)'")
    }

    // Resolve every secret before failing so one build surfaces every missing or empty
    // variable, not one per fix-rebuild cycle. Each failure gets its own `error:` line
    // (one issue each in Xcode); a missing one also gets its typo-hunting note.
    var resolved: [(name: String, value: String)] = []
    var failures: [ConfigError] = []
    for secret in secrets {
        // Ahead of resolution so it also explains a value overridden to "" that then fails.
        if captured.overriddenKeys.contains(secret.envVar) {
            // Never print either value — only that the file's copy lost.
            emit(
                "warning: \(secret.envVar) from the build environment overrides the different value "
                    + "\(envFileURL.path) exports; if the file is current, restart the terminal "
                    + "or Xcode session that launched this build"
            )
        }
        do {
            resolved.append(try resolveSecret(secret, environment: environment))
        } catch {
            if case .missingEnvironmentVariable = error {
                emit("note: \(missingEnvVarDiagnostic(envVar: secret.envVar, environment: environment))")
            }
            emit(error.diagnostic)
            failures.append(error)
        }
    }
    if failures.contains(where: { if case .missingEnvironmentVariable = $0 { true } else { false } }) {
        emit("note: set the missing variable(s) in your shell, ~/.zshenv (for Xcode.app), or your CI environment")
    }
    if failures.contains(where: { if case .emptyEnvironmentVariable = $0 { true } else { false } }) {
        // Inside the build sandbox a `$(security …)` or `$(op read …)` export fails with
        // status 0 and yields "", which would otherwise ship an empty API key.
        emit(
            "note: an empty value usually comes from a leftover `export KEY=` or a `$(…)` substitution "
                + "in the env file that failed inside the build sandbox; use a literal value, or append '?' "
                + "to the variable's name in Secrets.yml (`KEY?`) if empty is intended"
        )
    }
    if !failures.isEmpty {
        return false
    }

    let output = Data(renderSecretsEnum(resolved, environment: envName, access: configFile.access).utf8)
    let outputURL = URL(fileURLWithPath: outputPath)
    if let existing = try? Data(contentsOf: outputURL), existing == output {
        return true
    }
    do {
        try output.write(to: outputURL, options: .atomic)
    } catch {
        emit("error: failed to write \(outputPath): \(error.localizedDescription)")
        return false
    }
    return true
}
