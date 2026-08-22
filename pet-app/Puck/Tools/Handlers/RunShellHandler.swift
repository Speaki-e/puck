//
//  RunShellHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Process + /bin/zsh -lc, returns stdout/stderr/exit code
//

import Foundation

/// args: `{"command": "..."}`. Approval-gated per the tool registry (except a
/// whitelist) — approval itself happens upstream in the agent core; this
/// handler only executes.
final class RunShellHandler: ToolHandler {
    let toolName = "run_shell"

    /// How long a SIGTERM'd process gets before cancel() escalates to
    /// SIGKILL. Process.terminate() alone left a command that traps/ignores
    /// SIGTERM running forever despite the caller already being told
    /// "cancelled" (found via review) -- this is the highest-privilege tool
    /// in the registry, so its cancel guarantee shouldn't be defeatable by a
    /// trap.
    static var killGracePeriod: TimeInterval = 0.5

    /// The shell every command runs under. A `var` only so a test can point it
    /// at something that cannot launch -- a failed `run()` is otherwise
    /// unreachable from outside, and it is the path that used to leave a
    /// never-launched Process behind for the next cancel() to crash on.
    static var shellPath = "/bin/zsh"

    /// One dispatch's shell.
    ///
    /// `process` is published before `run()` launches it -- those happen on
    /// different queues -- so between the two it is a Process object with no
    /// child behind it. terminate() on one of those raises
    /// NSInvalidArgumentException, an ObjC exception, which in Swift is a
    /// crash the call site cannot catch, so `cancel` checks `isRunning` and
    /// leaves `isCancelled` behind instead; the launch side reads it and kills
    /// the child as soon as there is one. Without that a cancel landing in the
    /// window either crashed the app or was silently dropped, leaving the
    /// highest-privilege tool in the registry running with nobody able to
    /// stop it.
    private final class Call {
        var process: Process?
        var isCancelled = false
    }

    /// Keyed by dispatch id, because one handler instance serves every
    /// run_shell call. Held as a single in-flight process, a 60s timeout for
    /// call A fired `terminate` on whatever process call B had just started,
    /// and left A's own shell running unreachable.
    ///
    /// `execute` adds on whatever queue the caller runs on, the background
    /// block removes on completion, and `cancel` can arrive from ToolExecutor's
    /// own queue -- three different execution contexts, so access is guarded
    /// rather than a bare stored property.
    private let stateQueue = DispatchQueue(label: "Puck.RunShellHandler.state")
    private var calls: [String: Call] = [:]

    func cancel(id: String) {
        let process: Process? = stateQueue.sync {
            guard let call = calls[id] else { return nil }
            call.isCancelled = true
            return call.process
        }
        guard let process, process.isRunning else { return }
        terminate(process)
    }

    /// SIGTERM now, SIGKILL if it is still there after the grace period.
    private func terminate(_ process: Process) {
        process.terminate()

        // Foundation's Process places the child in its own new process
        // group, so signaling -pid reaches backgrounded grandchildren too
        // (same reasoning as terminate() itself, see RunShellHandlerTests).
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGracePeriod) {
            guard process.isRunning else { return }
            kill(-pid, SIGKILL)
        }
    }

    func execute(id: String, args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let command = args.extractString(key: "command") else {
            completion(.failure(.executionFailed("run_shell requires a command string")))
            return
        }

        let process = Process()
        let call = Call()
        stateQueue.sync {
            call.process = process
            calls[id] = call
        }
        process.executableURL = URL(fileURLWithPath: Self.shellPath)
        process.arguments = ["-lc", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        DispatchQueue.global().async {
            do {
                try process.run()
                // A cancel that landed while this was still queued could not
                // touch the process, so honour it here now that there is one.
                if self.stateQueue.sync(execute: { call.isCancelled }) {
                    self.terminate(process)
                }

                // Both pipes must be drained *while* the child runs, not after
                // it exits. A child writing past the OS pipe buffer (64KB on
                // macOS) blocks in write() until someone reads, so waiting for
                // exit first deadlocks — and stderr fills independently, so
                // draining only stdout deadlocks a stderr-noisy command just
                // the same. readDataToEndOfFile returns at EOF (child exit),
                // so reading both concurrently also serves as the wait.
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                let stderrQueue = DispatchQueue(label: "Puck.RunShellHandler.stderr")
                var stderrData = Data()
                stderrQueue.async { stderrData = stderrHandle.readDataToEndOfFile() }

                let stdoutData = stdoutHandle.readDataToEndOfFile()
                stderrQueue.sync {} // barrier: stderrData is fully written past this point

                process.waitUntilExit()
                self.stateQueue.sync { self.calls[id] = nil }
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
                // Cleared on the failure path too: left behind, a Process that
                // never launched stays this call's "in-flight" one, and a
                // cancel for the same id would try to terminate it.
                self.stateQueue.sync { self.calls[id] = nil }
                completion(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
}
