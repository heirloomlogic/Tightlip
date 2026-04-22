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

/// An error surfaced by the HeirloomSecrets tool during config parsing or env-var resolution.
public enum ConfigError: Error, Equatable, Sendable {
    /// The config file did not match the accepted grammar.
    ///
    /// `path` is echoed back in ``message``. `line` is the 1-indexed offending line, or `nil`
    /// for whole-file errors (e.g. a file with no declared secrets). `reason` is a short
    /// human-readable explanation.
    case parse(path: String, line: Int?, reason: String)

    /// A declared secret's environment variable was not set when the build tool ran.
    ///
    /// `envVar` is the missing variable. `property` is the fully-qualified Swift property
    /// name the value would have populated (e.g. `Secrets.revenueCatAPIKey`).
    case missingEnvironmentVariable(envVar: String, property: String)

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
        }
    }
}

/// Parses a HeirloomSecrets YAML config into an ordered list of secrets.
///
/// The accepted grammar is intentionally minimal (see `README.md > Config format`):
/// flat `name: ENV_VAR` mappings, `#` line comments, and blank lines. CRLF line
/// endings are normalized to LF. Anything else is a parse error.
///
/// - Parameters:
///   - text: Full config file contents.
///   - path: Path of the config file, echoed in any thrown error.
/// - Returns: Parsed secrets in source order.
/// - Throws: ``ConfigError/parse(path:line:reason:)`` on any grammar violation.
public func parseYAMLConfig(_ text: String, path: String) throws(ConfigError) -> [ParsedSecret] {
    var seen: [String: Int] = [:]
    var result: [ParsedSecret] = []

    let lines = text.components(separatedBy: "\n")
    for (idx, rawLineRaw) in lines.enumerated() {
        let lineNumber = idx + 1
        var rawLine = rawLineRaw
        if rawLine.hasSuffix("\r") { rawLine.removeLast() }

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
/// - Parameter resolved: Name/value pairs.
/// - Returns: Complete Swift source text, terminated with a trailing newline.
public func renderSecretsEnum(_ resolved: [(name: String, value: String)]) -> String {
    let properties =
        resolved
        .sorted { $0.name < $1.name }
        .map { "    static let \($0.name): String = \(encodeSwiftLiteral($0.value))" }
        .joined(separator: "\n")

    return """
        // Auto-generated by HeirloomSecrets. Do not edit.
        // Regenerated on every build from environment variables.

        nonisolated enum Secrets {
        \(properties)
        }

        """
}
