import Foundation
import PackagePlugin

@main
struct Lipservice: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "LipserviceTool")
        return [
            makeCommand(
                executable: tool.url,
                configURL: sourceTarget.directoryURL.appending(path: "Secrets.yml"),
                workDirectory: context.pluginWorkDirectoryURL,
                displayName: target.name,
                resources: resourcePaths(sourceTarget.sourceFiles)
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension Lipservice: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "LipserviceTool")
        let configURL = context.xcodeProject.directoryURL
            .appending(path: target.displayName)
            .appending(path: "Secrets.yml")
        return [
            makeCommand(
                executable: tool.url,
                configURL: configURL,
                workDirectory: context.pluginWorkDirectoryURL,
                displayName: target.displayName,
                resources: resourcePaths(target.inputFiles)
            )
        ]
    }
}
#endif

private func makeCommand(
    executable: URL,
    configURL: URL,
    workDirectory: URL,
    displayName: String,
    resources: [String]
) -> Command {
    let outputURL = workDirectory.appending(path: "Tightlip.swift")
    var arguments = [configURL.path(percentEncoded: false), outputURL.path(percentEncoded: false)]
    var inputFiles: [URL] = []

    // A declared input that doesn't exist fails package builds before the tool runs,
    // with a build-system error that never mentions Tightlip. Leaving it out lets the
    // tool's own "config missing" error through; the plugin runs at every build plan,
    // so tracking starts with the first build after the file appears.
    if isRegularFile(configURL) {
        inputFiles.append(configURL)
    }
    if isBundled(configURL.standardizedFileURL, resources: resources) {
        Diagnostics.warning(
            "Secrets.yml is copied into the \(displayName) bundle as a resource, exposing the "
                + "environment variable names it declares. Remove it from the target "
                + "(File inspector → Target Membership); the plugin reads it from disk.",
            file: configURL.path(percentEncoded: false)
        )
    }
    if let configText = try? String(contentsOf: configURL, encoding: .utf8) {
        let configLines = configText.components(separatedBy: "\n")
        if let envFile = envFileInput(configLines: configLines, configURL: configURL) {
            inputFiles.append(envFile)
            if isBundled(envFile, resources: resources) {
                Diagnostics.error(
                    "\(envFile.lastPathComponent) is copied into the \(displayName) bundle as a resource, "
                        + "which would ship its plaintext secrets. Remove it from the target "
                        + "(File inspector → Target Membership) or move it outside the target's folder.",
                    file: envFile.path(percentEncoded: false)
                )
            }
        }
        let forwardedURL = workDirectory.appending(path: "forwarded-environment")
        if writeForwardedEnvironment(configLines: configLines, to: forwardedURL) {
            arguments.append(forwardedURL.path(percentEncoded: false))
            inputFiles.append(forwardedURL)
        }
    }

    return .buildCommand(
        displayName: "Lipservice (\(displayName))",
        executable: executable,
        arguments: arguments,
        inputFiles: inputFiles,
        outputFiles: [outputURL]
    )
}

/// Locates the env file the tool will source, so edits to it re-trigger generation.
///
/// This mirrors TightlipCore's directive recognition (`extractEnvFileDirective`) and
/// path resolution (`resolveEnvFilePath`) just closely enough for input tracking.
/// Plugins can't depend on library targets, so the duplication is deliberate and
/// fail-open: if this scan ever disagrees with the real parser, the worst case is
/// input tracking as stale as it was before this existed — the tool remains the sole
/// source of truth for build output.
private func envFileInput(configLines: [String], configURL: URL) -> URL? {
    var declared: String?
    for rawLine in configLines {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty || stripped.hasPrefix("#") { continue }
        if line.first?.isWhitespace == false, stripped.hasPrefix("envFile:") {
            declared = String(stripped.dropFirst("envFile:".count))
                .trimmingCharacters(in: .whitespaces)
        }
        break
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let resolved: URL
    switch declared {
    case nil:
        resolved = home.appending(path: ".zshenv")
    case let path? where path.hasPrefix("~/"):
        resolved = home.appending(path: String(path.dropFirst(2)))
    case let path? where path.hasPrefix("/"):
        resolved = URL(fileURLWithPath: path)
    case let path?:
        resolved = configURL.deletingLastPathComponent().appending(path: path)
    }

    // Declaring a nonexistent input file makes the build error rather than skip, and a
    // directory would re-trigger generation whenever any entry in it changes. This runs
    // at every build plan, so tracking self-heals on the first build after the file
    // appears.
    let standardized = resolved.standardizedFileURL
    return isRegularFile(standardized) ? standardized : nil
}

/// Copies the environment variables the config names (plus `TIGHTLIP_ENV`) from the
/// plugin's own environment into a build input the tool reads.
///
/// Two build-system behaviors make this necessary. SwiftPM's `swiftbuild` backend runs
/// build commands in a synthesized environment, so without it a variable exported by
/// the caller (a CI job's `env:` block) never reaches the tool. And variables aren't
/// files the build system can watch, so without it changing `TIGHTLIP_ENV` or a secret's
/// value leaves the previous output in place. The file is rewritten only when its
/// contents change — a changed value re-runs the tool; an unchanged one doesn't.
///
/// Values travel through a 0600 file rather than `Command`'s `environment:`, which
/// `xcodebuild` echoes into build logs. The file holds plaintext values for every
/// section's variables — the plugin can't know which section the tool will select — so
/// it is the most sensitive file in the build directory.
///
/// Returns whether the file is in place. On any failure, the tool falls back to its own
/// environment — exactly the behavior before forwarding existed.
private func writeForwardedEnvironment(configLines: [String], to url: URL) -> Bool {
    let environment = ProcessInfo.processInfo.environment
    var entries = Data()
    for name in forwardedNames(configLines: configLines).sorted() {
        guard let value = environment[name] else { continue }
        entries.append(Data("\(name)=\(value)".utf8))
        entries.append(0)
    }

    let path = url.path(percentEncoded: false)
    var status = stat()
    if lstat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_mode & 0o077 == 0,
        FileManager.default.contents(atPath: path) == entries
    {
        return true
    }
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    // Created 0600 from the first byte (FileManager.createFile applies permissions only
    // after writing), exclusively and without following a planted symlink, then renamed
    // over the destination.
    let temporary = url.deletingLastPathComponent()
        .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        .path(percentEncoded: false)
    let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { return false }
    let written = entries.withUnsafeBytes { buffer in
        buffer.isEmpty ? 0 : write(fd, buffer.baseAddress, buffer.count)
    }
    close(fd)
    guard written == entries.count, rename(temporary, path) == 0 else {
        unlink(temporary)
        return false
    }
    return true
}

/// Every identifier on the right of a `name: VALUE` line, in any section, plus
/// `TIGHTLIP_ENV`. Deliberately looser than the real grammar: an extra name only costs
/// an unused entry, and the tool rejects malformed configs anyway.
private func forwardedNames(configLines: [String]) -> Set<String> {
    var names: Set<String> = ["TIGHTLIP_ENV"]
    for rawLine in configLines {
        let stripped = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { continue }
        guard let colon = stripped.firstIndex(of: ":") else { continue }
        let value = stripped[stripped.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if isIdentifier(value) {
            names.insert(value)
        }
    }
    return names
}

private func isIdentifier(_ s: String) -> Bool {
    guard let first = s.first, first.isASCII, first.isLetter || first == "_" else { return false }
    return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
}

/// Files the target copies into its product as resources. Xcode's synchronized folders
/// (the default for new targets) do this to every non-source file in the folder —
/// including `Secrets.yml` and a project-local env file.
private func resourcePaths(_ files: FileList) -> [String] {
    files.filter { $0.type == .resource }.map { $0.url.standardizedFileURL.path(percentEncoded: false) }
}

/// Whether `file` is a resource itself or sits inside a directory resource (a SwiftPM
/// `.copy("Config")`, an Xcode folder reference).
private func isBundled(_ file: URL, resources: [String]) -> Bool {
    let path = file.path(percentEncoded: false)
    return resources.contains { resourcePath in
        path == resourcePath || path.hasPrefix(resourcePath.hasSuffix("/") ? resourcePath : resourcePath + "/")
    }
}

private func isRegularFile(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
    return exists && !isDirectory.boolValue
}
