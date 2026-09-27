import Foundation
import TightlipCore

@main
struct LipserviceTool {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 || args.count == 4 else {
            FileHandle.standardError.write(
                Data("error: usage: LipserviceTool <config.yml> <output.swift> [<forwarded-env>]\n".utf8)
            )
            exit(1)
        }
        let succeeded = generateSecretsFile(
            configPath: args[1],
            outputPath: args[2],
            forwardedEnvironmentPath: args.count == 4 ? args[3] : nil,
            processEnvironment: ProcessInfo.processInfo.environment,
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory()),
            emit: { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
        )
        exit(succeeded ? 0 : 1)
    }
}
