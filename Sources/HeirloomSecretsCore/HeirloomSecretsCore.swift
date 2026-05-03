import Foundation

/// A single secret declared in a HeirloomSecrets YAML config.
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

/// The result of parsing a HeirloomSecrets YAML config file.
public enum ParsedConfig: Equatable, Sendable {
    /// Flat format: a simple list of property → env-var mappings.
    case flat([ParsedSecret])

    /// Sectioned format: named environments, each containing identical property sets.
    case sectioned([(name: String, secrets: [ParsedSecret])])

    /// Compares two parsed configs for structural equality.
    public static func == (lhs: ParsedConfig, rhs: ParsedConfig) -> Bool {
        switch (lhs, rhs) {
        case (.flat(let a), .flat(let b)):
            return a == b
        case (.sectioned(let a), .sectioned(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.name == $1.name && $0.secrets == $1.secrets }
        default:
            return false
        }
    }
}

/// An error surfaced by the HeirloomSecrets tool during config parsing or env-var resolution.
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
            return """
                environment variable \(envVar) must be set to generate \(property). \
                Set it in your shell, ~/.zshenv (for Xcode.app), or your CI environment.
                """
        case .indeterminateEnvironment(let available, let reason):
            return """
                cannot determine environment: \(reason). \
                Available environments: \(available.joined(separator: ", ")). \
                Set HEIRLOOM_ENV to one of these values.
                """
        }
    }
}

/// Parses a HeirloomSecrets YAML config, returning either a flat or sectioned result.
///
/// The format is auto-detected from the first meaningful line:
/// - If it matches `identifier:` with no value, the file is **sectioned** (environments).
/// - Otherwise, it's the classic **flat** format.
///
/// - Parameters:
///   - text: Full config file contents.
///   - path: Path of the config file, echoed in any thrown error.
/// - Returns: A ``ParsedConfig`` representing the file contents.
/// - Throws: ``ConfigError/parse(path:line:reason:)`` on any grammar violation.
public func parseYAMLConfig(_ text: String, path: String) throws(ConfigError) -> ParsedConfig {
    let lines = text.components(separatedBy: "\n")
    let normalized = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }

    let firstMeaningful = normalized.first {
        let s = $0.trimmingCharacters(in: .whitespaces)
        return !s.isEmpty && !s.hasPrefix("#")
    }

    guard let first = firstMeaningful else {
        throw .parse(path: path, line: nil, reason: "no secrets declared")
    }

    if isSectionHeader(first) {
        return .sectioned(try parseSectioned(normalized, path: path))
    }
    return .flat(try parseFlat(normalized, path: path))
}

/// Legacy convenience that returns secrets directly for flat configs.
public func parseFlatYAMLConfig(_ text: String, path: String) throws(ConfigError) -> [ParsedSecret] {
    let config = try parseYAMLConfig(text, path: path)
    switch config {
    case .flat(let secrets): return secrets
    case .sectioned: throw .parse(path: path, line: nil, reason: "expected flat config but found environment sections")
    }
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
) throws(ConfigError) -> [(name: String, secrets: [ParsedSecret])] {
    var sections: [(name: String, secrets: [ParsedSecret])] = []
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
                sections.append((name: prev, secrets: currentSecrets))
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
        sections.append((name: prev, secrets: currentSecrets))
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
/// 1. `HEIRLOOM_ENV` — explicit override, used directly.
/// 2. `CONFIGURATION` (set by Xcode) — inferred when exactly two sections exist and one is
///    named `prod` or `production`. `Release` maps to that section; anything else maps to the other.
/// 3. Error if neither mechanism resolves.
public func resolveEnvironment(
    sections: [(name: String, secrets: [ParsedSecret])],
    environment: [String: String]
) throws(ConfigError) -> String {
    let sectionNames = sections.map(\.name)

    if let explicit = environment["HEIRLOOM_ENV"], !explicit.isEmpty {
        guard sectionNames.contains(explicit) else {
            throw .indeterminateEnvironment(
                available: sectionNames,
                reason: "HEIRLOOM_ENV='\(explicit)' does not match any section"
            )
        }
        return explicit
    }

    if sectionNames.count == 2 {
        let prodName = sectionNames.first { $0 == "prod" || $0 == "production" }
        if let prodName, let otherName = sectionNames.first(where: { $0 != prodName }) {
            let configuration = environment["CONFIGURATION"] ?? ""
            if configuration.lowercased() == "release" {
                return prodName
            }
            return otherName
        }
    }

    throw .indeterminateEnvironment(
        available: sectionNames,
        reason: "HEIRLOOM_ENV is not set and automatic inference is not possible"
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

/// Wraps `value` as a Swift string literal, escaping control characters and quotes.
///
/// Uses named escapes (`\\`, `\"`, `\n`, `\r`, `\t`, `\0`) where available; other
/// characters below U+0020 and U+007F (DEL) are emitted as `\u{HEX}`. Printable ASCII
/// and characters at or above U+0080 pass through unchanged.
///
/// - Parameter value: The raw string to encode.
/// - Returns: A double-quoted Swift string literal whose parse equals `value`.
public func encodeSwiftLiteral(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\\": result += "\\\\"
        case "\"": result += "\\\""
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        case "\0": result += "\\0"
        default:
            if scalar.value < 0x20 || scalar.value == 0x7F {
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }
    result += "\""
    return result
}

/// Renders the generated `nonisolated enum Secrets { ... }` Swift source.
///
/// Properties are emitted in alphabetical order; values are escaped via
/// ``encodeSwiftLiteral(_:)``.
///
/// - Parameters:
///   - resolved: Name/value pairs.
///   - environment: If non-nil, annotates the header with the active environment name.
/// - Returns: Complete Swift source text, terminated with a trailing newline.
public func renderSecretsEnum(
    _ resolved: [(name: String, value: String)],
    environment: String? = nil
) -> String {
    let properties =
        resolved
        .sorted { $0.name < $1.name }
        .map { "    static let \($0.name): String = \(encodeSwiftLiteral($0.value))" }
        .joined(separator: "\n")

    let envLine = environment.map { "\n// Environment: \($0)" } ?? ""

    return """
        // Auto-generated by HeirloomSecrets. Do not edit.
        // Regenerated on every build from environment variables.\(envLine)

        nonisolated enum Secrets {
        \(properties)
        }

        """
}
