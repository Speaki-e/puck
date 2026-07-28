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
    /// `execute` sets this on whatever queue the caller runs on, the
    /// background block clears it on completion, and `cancel()` can arrive
    /// from ToolExecutor's own queue -- three different execution contexts,
    /// so access is guarded rather than a bare stored property.
    private let stateQueue = DispatchQueue(label: "PetAgent.RunShellHandler.state")
    private var runningProcess: Process?

    func cancel() {
        stateQueue.sync { runningProcess }?.terminate()
        stateQueue.sync { runningProcess = nil }
    }

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let command = args.extractString(key: "command") else {
            completion(.failure(.executionFailed("run_shell requires a command string")))
            return
        }

        let process = Process()
        stateQueue.sync { runningProcess = process }
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
                self.stateQueue.sync { self.runningProcess = nil }
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
