import Foundation
import TightlipCore

@main
struct LipserviceTool {
    static func main() {
        let args = CommandLine.arguments
        let emit: (String) -> Void = { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
        let home = URL(fileURLWithPath: NSHomeDirectory())

        // `tightlip-check` mode. The report goes to stdout, diagnostics included, so the
        // two stay in order.
        if args.count == 4, args[1] == "--check" {
            let succeeded = checkSecretsConfig(
                configPath: args[3],
                displayName: args[2],
                processEnvironment: ProcessInfo.processInfo.environment,
                homeDirectory: home,
                emit: { FileHandle.standardOutput.write(Data("\($0)\n".utf8)) }
            )
            exit(succeeded ? 0 : 1)
        }

        guard args.count == 3 || args.count == 4 else {
            emit(
                "error: usage: LipserviceTool <config.yml> <output.swift> [<forwarded-env>]\n"
                    + "       LipserviceTool --check <target-name> <config.yml>"
            )
            exit(1)
        }
        let succeeded = generateSecretsFile(
            configPath: args[1],
            outputPath: args[2],
            forwardedEnvironmentPath: args.count == 4 ? args[3] : nil,
            processEnvironment: ProcessInfo.processInfo.environment,
            homeDirectory: home,
            emit: emit
        )
        exit(succeeded ? 0 : 1)
    }
}
