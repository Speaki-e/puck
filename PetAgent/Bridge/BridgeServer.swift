//
//  BridgeServer.swift
//  PetAgent
//
//  F11/socket · owner: Haeyoung Park
//  Network.framework NWListener(UDS) at ~/Library/Application Support/PetAgent/bridge.sock
//

import Foundation
import Network

enum BridgeServerError: Error, Equatable {
    /// Another pet-app process already holds this socket (its lock file names
    /// a still-alive PID). Refuse to steal the socket out from under it.
    case alreadyRunning
}

/// Runs the JSON Lines Unix-domain-socket server pet-app exposes to workspace
/// (protocol repo section 2: "서버: pet-app (NWListener)"). workspace connects
/// as a client and reconnects with exponential backoff on its own; pet-app's
/// job is just to accept connections and stay a pure pet when none are open.
final class BridgeServer {
    static let defaultSocketURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PetAgent", isDirectory: true).appendingPathComponent("bridge.sock")
    }()

    /// All access to `connections` (reads and writes) must go through `queue` —
    /// accept()/per-connection onClose already run there; `stop()` and any
    /// external read are the ones that must explicitly hop onto it too.
    private var connections: [BridgeConnection] = []
    private var listener: NWListener?
    private let socketURL: URL
    private var lockFileURL: URL { socketURL.appendingPathExtension("lock") }
    private let queue = DispatchQueue(label: "PetAgent.BridgeServer")

    /// Called for every message from any connected client, along with which
    /// connection it came from (so a reply can be sent back to that client).
    var onMessage: ((BridgeMessage, BridgeConnection) -> Void)?

    /// Called if the listener fails to bind/listen, or drops into `.waiting`
    /// (e.g. permission denied) — NWListener reports these asynchronously via
    /// stateUpdateHandler; a successful `start()` return does NOT mean the
    /// socket is actually listening yet.
    var onFailure: ((Error) -> Void)?

    init(socketURL: URL = BridgeServer.defaultSocketURL) {
        self.socketURL = socketURL
    }

    func start() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard !Self.isPetAppRunning(lockFileURL: lockFileURL) else {
            throw BridgeServerError.alreadyRunning
        }
        try? FileManager.default.removeItem(at: socketURL) // stale socket file from a previous (now-dead) run
        Self.writeLockFile(at: lockFileURL, pid: ProcessInfo.processInfo.processIdentifier)

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketURL.path)

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if let error = Self.failureError(for: state) {
                self?.onFailure?(error)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        try? FileManager.default.removeItem(at: lockFileURL)
    }

    /// Thread-safe snapshot of currently-open connections.
    func currentConnections() -> [BridgeConnection] {
        queue.sync { connections }
    }

    private func accept(_ nwConnection: NWConnection) {
        // Runs on `queue` (newConnectionHandler fires on the queue passed to
        // listener.start), same as onClose below — safe to mutate directly.
        let connection = BridgeConnection(connection: nwConnection)
        connection.onMessage = { [weak self, weak connection] message in
            guard let self, let connection else { return }
            self.onMessage?(message, connection)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.connections.removeAll { $0 === connection }
        }
        connections.append(connection)
        connection.start(queue: queue)
    }

    // MARK: - Listener failure mapping (pure, testable independent of real bind failures)

    static func failureError(for state: NWListener.State) -> Error? {
        switch state {
        case .failed(let error), .waiting(let error):
            return error
        default:
            return nil
        }
    }

    // MARK: - Single-instance guard

    /// Whether the lock file at `lockFileURL` names a PID that's still alive.
    /// `kill(pid, 0)` sends no signal; it only reports whether the process
    /// exists (and is signalable by us).
    static func isPetAppRunning(lockFileURL: URL) -> Bool {
        guard
            let data = try? Data(contentsOf: lockFileURL),
            let pidString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = pid_t(pidString)
        else {
            return false
        }
        return kill(pid, 0) == 0
    }

    private static func writeLockFile(at url: URL, pid: Int32) {
        try? Data(String(pid).utf8).write(to: url)
    }
}
