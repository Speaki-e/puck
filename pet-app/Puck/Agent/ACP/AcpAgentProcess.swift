//
//  AcpAgentProcess.swift
//  Puck
//
//  Spawns a vendored ACP agent under node and wires its stdio to an
//  AcpConnection. The process half of workspace/src/agent-host/acp-adapter.ts.
//
//  Environment is deliberately minimal, same as the TS version: PATH,
//  NODE_ENV, whatever the selected agent needs to find its credentials, and
//  nothing else. Handing an agent the full parent environment would give a
//  subprocess every secret this app happens to be holding.
//

import Foundation

final class AcpAgentProcess {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stderrLock = NSLock()
    private var stderrTail = ""

    let connection: AcpConnection

    /// Fires once, when the process exits for any reason. Carries the tail of
    /// stderr, which is what turns "it died" into something diagnosable.
    var onExit: ((_ status: Int32, _ stderrTail: String) -> Void)?

    init(command: AcpAgentCommand, projectPath: String, credentials: [String: String]) {
        connection = AcpConnection(send: { [stdinPipe] data in
            // The agent can exit between our decision to write and the write
            // itself; a closed pipe raises SIGPIPE through FileHandle, and an
            // agent that already died is not worth crashing over.
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        })

        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "NODE_ENV": "production",
            // The agents write scratch state under HOME; without it they fall
            // back to "/" and fail in ways that read as protocol errors.
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
        ]
        environment.merge(command.extraEnvironment) { _, new in new }
        environment.merge(credentials) { _, new in new }
        process.environment = environment
    }

    func start() throws {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [connection] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            connection.receive(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self, let text = String(data: data, encoding: .utf8) else { return }
            self.stderrLock.lock()
            // Bounded the same way the TS version bounded it: the last 8KB is
            // enough to explain a crash, and an agent that logs in a loop must
            // not grow this without limit.
            self.stderrTail = String((self.stderrTail + text).suffix(8_192))
            self.stderrLock.unlock()
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe.fileHandleForReading.readabilityHandler = nil
            let tail = self.currentStderrTail()
            self.connection.failAllPending(with: AcpError.processExited(detail: tail))
            self.onExit?(process.terminationStatus, tail)
        }
        try process.run()
    }

    func currentStderrTail() -> String {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        return stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    /// SIGKILL. Only for the case where `session/cancel` plus SIGTERM did not
    /// end it -- see AcpCodeEditorSession's cancel path.
    func kill() {
        guard process.isRunning else { return }
        Foundation.kill(process.processIdentifier, SIGKILL)
    }
}
