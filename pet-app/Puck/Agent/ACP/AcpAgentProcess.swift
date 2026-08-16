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

/// What CodeEditorRunner needs from a running agent. Exists so the queue and
/// cancellation logic can be tested against a scripted stream -- spawning node
/// to prove that two runs on one workspace serialise would be testing the
/// wrong thing, slowly.
protocol AcpAgentTransport: AnyObject {
    var connection: AcpConnection { get }
    var isRunning: Bool { get }
    func terminate()
    func kill()
}

final class AcpAgentProcess: AcpAgentTransport {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stderrLock = NSLock()
    private var stderrTail = ""

    let connection: AcpConnection
    /// What the child was given. Exposed so the trimming can be asserted --
    /// too little breaks the vendor CLI's login, too much hands a subprocess
    /// secrets it has no business seeing.
    private(set) var childEnvironment: [String: String] = [:]

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
            // Required, and not obviously so: the vendor CLIs look their saved
            // login up in the macOS Keychain by account name, and USER is
            // where they read it. Without it a perfectly logged-in `claude`
            // reports "Not logged in", which arrives here as ACP error -32000
            // "Authentication required" -- a message that sends you looking
            // for a missing API key rather than a missing variable.
            "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
        ]
        environment.merge(command.extraEnvironment) { _, new in new }
        environment.merge(credentials) { _, new in new }
        process.environment = environment
        childEnvironment = environment
    }

    func start() throws {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [connection] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            connection.receive(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.appendStderr(data)
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe.fileHandleForReading.readabilityHandler = nil
            // What the child wrote just before exiting is still sitting in the
            // pipe when this fires, and the reader is now gone. Left unread it
            // is usually the reply that finished the run, so a run that
            // succeeded would be reported as "the process exited".
            self.drainRemainingOutput()
            let tail = self.currentStderrTail()
            self.connection.failAllPending(with: AcpError.processExited(detail: tail))
            self.onExit?(process.terminationStatus, tail)
        }
        try process.run()
    }

    private func appendStderr(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        stderrLock.lock()
        // Bounded the same way the TS version bounded it: the last 8KB is
        // enough to explain a crash, and an agent that logs in a loop must
        // not grow this without limit.
        stderrTail = String((stderrTail + text).suffix(8_192))
        stderrLock.unlock()
    }

    /// Everything both pipes still hold, after the readers are detached.
    private func drainRemainingOutput() {
        drainBuffered(stdoutPipe.fileHandleForReading) { [connection] data in connection.receive(data) }
        drainBuffered(stderrPipe.fileHandleForReading) { [weak self] data in self?.appendStderr(data) }
    }

    /// Reads what is already buffered, without blocking. Non-blocking on
    /// purpose: the child has exited so everything it wrote is in the pipe
    /// already, while a blocking read to EOF would wait on any grandchild that
    /// inherited the write end -- the vendor CLI the agent spawns is exactly
    /// that -- and never come back.
    private func drainBuffered(_ handle: FileHandle, into sink: (Data) -> Void) {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else { return }
        defer { _ = fcntl(descriptor, F_SETFL, flags) }

        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                sink(Data(buffer[0..<count]))
            } else if count == -1 && errno == EINTR {
                continue
            } else {
                return
            }
        }
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
