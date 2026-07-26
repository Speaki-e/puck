//
//  RunShellHandler.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  Process + /bin/zsh -lc, returns stdout/stderr/exit code
//

import Foundation

/// args: `{"command": "..."}`. Approval-gated per the tool registry (except a
/// whitelist) — approval itself happens upstream in the agent core; this
/// handler only executes.
final class RunShellHandler: ToolHandler {
    let toolName = "run_shell"

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard case .object(let fields) = args, case .string(let command) = fields["command"] else {
            completion(.failure(.executionFailed("run_shell requires a command string")))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        DispatchQueue.global().async {
            do {
                try process.run()
                process.waitUntilExit()
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                completion(
                    .success(
                        .object([
                            "stdout": .string(stdout),
                            "stderr": .string(stderr),
                            "exit_code": .number(Double(process.terminationStatus)),
                        ])
                    )
                )
            } catch {
                completion(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
}
