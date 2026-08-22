//
//  BridgeServer.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Network.framework NWListener(UDS) at ~/Library/Application Support/Puck/bridge.sock
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
    static let defaultSocketURL: URL = BridgeSocketPath.default

    /// All access to `connections` (reads and writes) must go through `queue` —
    /// accept()/per-connection onClose already run there; `stop()` and any
    /// external read are the ones that must explicitly hop onto it too.
    private var connections: [BridgeConnection] = []
    private var listener: NWListener?
    private let socketURL: URL
    private var lockFileURL: URL { socketURL.appendingPathExtension("lock") }
    private let queue = DispatchQueue(label: "Puck.BridgeServer")

    /// Called for every message from any connected client, along with which
    /// connection it came from (so a reply can be sent back to that client).
    var onMessage: ((BridgeMessage, BridgeConnection) -> Void)?

    /// Called if the listener fails to bind/listen, or drops into `.waiting`
    /// (e.g. permission denied) — NWListener reports these asynchronously via
    /// stateUpdateHandler; a successful `start()` return does NOT mean the
    /// socket is actually listening yet.
    var onFailure: ((Error) -> Void)?

    /// Forwarded from BridgeConnection.onMalformedLine -- a dropped line
    /// otherwise produced zero operational signal, indistinguishable from
    /// "the tool is just slow" until ToolExecutor's own timeout (found via
    /// review).
    var onMalformedLine: (() -> Void)?

    /// Fires when the number of gui-role connections transitions between
    /// zero and non-zero -- true on the first one connecting, false once the
    /// last one disconnects (protocol 3.7, 2026-07-30). NOT wired to
    /// pin/unpin the character: PuckClient is a Dock-resident app
    /// expected to stay running continuously, so tying the pin to "is a gui connected" would freeze
    /// the pet in place for as long as PuckClient is alive, not just
    /// while its window is actually being used. Pin/unpin stays with the
    /// local, in-process quick-capture bubble (Option+Shift+Space), which
    /// is the one truly momentary interaction pet-app can observe directly.
    var onGUIPresenceChanged: ((Bool) -> Void)?
    private var lastGUIPresence = false

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

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketURL.path)

        // Written only once NWListener construction has actually succeeded --
        // writing it earlier meant a throw here left a lock file naming this
        // still-alive process, permanently blocking every later start() call
        // in the same process with a false alreadyRunning.
        let listener = try NWListener(using: parameters)
        Self.writeLockFile(at: lockFileURL, pid: ProcessInfo.processInfo.processIdentifier)
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.restrictSocketPermissions()
            }
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
        // NWListener.cancel() does not unlink the bound path, so the socket
        // file outlives the process unless removed here. start() also clears a
        // stale one, but only the *next* launch gets there — without this a
        // dead endpoint sits in Application Support after every quit, and a
        // client can connect to a path nothing is listening on.
        try? FileManager.default.removeItem(at: socketURL)
        try? FileManager.default.removeItem(at: lockFileURL)
    }

    /// Sends to just the connections playing `role`, and reports whether
    /// there were any. Used to mirror the quick-capture bubble's text into
    /// PuckClient's chat view (2026-07-30).
    ///
    /// Same constraint as `currentConnections()`: never call this from
    /// `queue` (i.e. not from inside `onMessage`/`onGUIPresenceChanged`).
    @discardableResult
    func send(_ message: BridgeMessage, to role: ClientRole) -> Bool {
        let targets = currentConnections().filter { $0.role == role }
        targets.forEach { $0.send(message) }
        return !targets.isEmpty
    }

    /// Thread-safe snapshot of currently-open connections.
    ///
    /// Uses `queue.sync`, so it must not be called from `queue` itself — i.e.
    /// never from inside an `onMessage` handler, which is delivered there.
    func currentConnections() -> [BridgeConnection] {
        queue.sync { connections }
    }

    private func accept(_ nwConnection: NWConnection) {
        // Runs on `queue` (newConnectionHandler fires on the queue passed to
        // listener.start), same as onClose below — safe to mutate directly.
        let connection = BridgeConnection(connection: nwConnection)
        connection.onMessage = { [weak self, weak connection] message in
            guard let self, let connection else { return }
            if case .clientHello(let role) = message {
                connection.role = role
                self.updateGUIPresence()
                return
            }
            self.relay(message, from: connection)
            self.onMessage?(message, connection)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.connections.removeAll { $0 === connection }
            self.updateGUIPresence()
        }
        connection.onMalformedLine = { [weak self] in self?.onMalformedLine?() }
        connections.append(connection)
        connection.start(queue: queue)
    }

    /// Forwards a message to every currently-connected role it's addressed
    /// to (protocol 3.7) -- pet-app relays rather than handling everything
    /// in-process now that the gui side can be a separate process
    /// (PuckClient) from workspace.
    private func relay(_ message: BridgeMessage, from origin: BridgeConnection) {
        guard let targetRole = ClientRelay.targetRole(for: message) else { return }
        for connection in connections where connection.role == targetRole {
            connection.send(message)
        }
    }

    /// Runs on `queue`, same as accept()/onClose -- only fires
    /// onGUIPresenceChanged on an actual zero<->non-zero transition, not
    /// every connect/disconnect (multiple gui connections are possible in
    /// principle, even if only one PuckClient is expected in practice).
    private func updateGUIPresence() {
        let hasGUI = connections.contains { $0.role == .gui }
        guard hasGUI != lastGUIPresence else { return }
        lastGUIPresence = hasGUI
        onGUIPresenceChanged?(hasGUI)
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

    /// The socket had no peer authentication and default permissions
    /// (srwxr-xr-x) -- any other local-user-owned process could connect and
    /// dispatch run_shell/run_applescript, bypassing ai-module's upstream
    /// approval UI entirely (found via review). Restricting to owner-only
    /// read/write at least closes it off to every other local account.
    private func restrictSocketPermissions() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: socketURL.path)
    }
}

// MARK: - UserInputTransport

extension BridgeServer: UserInputTransport {
    /// Read live rather than remembered: BridgeConnection.onClose removes a
    /// connection as soon as the transport reports it gone, so this flips to
    /// false the moment the client goes away.
    ///
    /// This counted *non*-gui connections until 2026-08-15, because the thing
    /// that acted on user input was workspace and PuckClient was only a chat
    /// view. Deleting workspace inverted that: PuckClient hosts the agent now,
    /// so it is the only connection that can act on anything, and counting
    /// anything else would report the pet's bubble as delivered into a void.
    var hasConnectedClients: Bool {
        !agentFacingConnections().isEmpty
    }

    /// One PuckClient is expected, but sending to every gui connection keeps
    /// this correct if a second one ever attaches (and costs nothing when
    /// there is one).
    ///
    /// Returns whether there was anyone to send to, queried fresh at this
    /// exact call -- a caller that pre-checked `hasConnectedClients` earlier
    /// can still race a disconnect landing in between (BridgeConnection.onClose
    /// runs on this same queue), so the true answer is decided here, not there.
    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool {
        let connections = agentFacingConnections()
        connections.forEach { $0.send(message) }
        return !connections.isEmpty
    }

    /// Connections that can act on user input -- gui ones, which is all that
    /// is left. A connection that has not sent client_hello yet has no role
    /// and does not count: it may never identify itself at all.
    private func agentFacingConnections() -> [BridgeConnection] {
        currentConnections().filter { $0.role == .gui }
    }
}
