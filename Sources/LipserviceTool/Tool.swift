import Foundation
import TightlipCore

@main
struct LipserviceTool {
    static func main() {
        let args = CommandLine.arguments
        let emit: (String) -> Void = { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
        guard args.count == 3 || args.count == 4 else {
            emit("error: usage: LipserviceTool <config.yml> <output.swift> [<forwarded-env>]")
            exit(1)
        }
        let succeeded = generateSecretsFile(
            configPath: args[1],
            outputPath: args[2],
            forwardedEnvironmentPath: args.count == 4 ? args[3] : nil,
            processEnvironment: ProcessInfo.processInfo.environment,
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory()),
            emit: emit
        )
        exit(succeeded ? 0 : 1)
    }
}
