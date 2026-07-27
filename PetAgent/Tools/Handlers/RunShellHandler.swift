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

    /// The in-flight process, so a timed-out call can actually kill it
    /// instead of leaving it running with nobody reading its pipes.
    private var runningProcess: Process?

    func cancel() {
        runningProcess?.terminate()
        runningProcess = nil
    }

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let command = args.extractString(key: "command") else {
            completion(.failure(.executionFailed("run_shell requires a command string")))
            return
        }

        let process = Process()
        runningProcess = process
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        DispatchQueue.global().async {
            do {
                try process.run()

                // Both pipes must be drained *while* the child runs, not after
                // it exits. A child writing past the OS pipe buffer (64KB on
                // macOS) blocks in write() until someone reads, so waiting for
                // exit first deadlocks — and stderr fills independently, so
                // draining only stdout deadlocks a stderr-noisy command just
                // the same. readDataToEndOfFile returns at EOF (child exit),
                // so reading both concurrently also serves as the wait.
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                let stderrQueue = DispatchQueue(label: "PetAgent.RunShellHandler.stderr")
                var stderrData = Data()
                stderrQueue.async { stderrData = stderrHandle.readDataToEndOfFile() }

                let stdoutData = stdoutHandle.readDataToEndOfFile()
                stderrQueue.sync {} // barrier: stderrData is fully written past this point

                process.waitUntilExit()
                self.runningProcess = nil
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
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
