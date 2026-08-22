//
//  BridgeSocketClient.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  PuckClient's own connection to bridge.sock (2026-07-30) -- unlike
//  BridgeServer (which pet-app hosts), this is the client side: it dials
//  out, announces role .gui (protocol 3.7) once ready, and reconnects with
//  the same exponential backoff (1s -> 2s -> 4s, capped at 30s) documented
//  for workspace's own client behavior (docs/socket.md).
//

import Foundation
import Network

final class BridgeSocketClient {
    /// Fires for every message the server relays to this connection
    /// (protocol 3.7 -- events, workspace_create, session_create,
    /// editor_view_ready, editor_view_unavailable).
    var onMessage: ((BridgeMessage) -> Void)?

    /// The connection dropped. Reconnection is handled here and needs no
    /// help, but anything waiting on a reply does: a tool_dispatch already on
    /// the wire can never be answered, because BridgeServer's relay sends
    /// replies back on the connection that received the dispatch and that
    /// connection is gone. Reconnecting does not recover it. Without this the
    /// dispatch waited out its full registry timeout -- 60s for run_shell --
    /// and reported "timeout" instead of "pet_app_disconnected".
    ///
    /// Fires on every drop, including the ones retried during startup before
    /// pet-app is up. That is harmless: failing nothing is a no-op.
    var onDisconnect: (() -> Void)?

    private let socketURL: URL
    private let queue = DispatchQueue(label: "PuckClient.BridgeSocketClient")
    private var connection: BridgeConnection?
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 30

    init(socketURL: URL = BridgeSocketPath.default) {
        self.socketURL = socketURL
    }

    func start() {
        queue.async { [weak self] in self?.connect() }
    }

    private func connect() {
        let nwConnection = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        let bridgeConnection = BridgeConnection(connection: nwConnection)
        bridgeConnection.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        bridgeConnection.onReady = { [weak self, weak bridgeConnection] in
            self?.reconnectDelay = 1
            bridgeConnection?.send(.clientHello(role: .gui))
        }
        bridgeConnection.onClose = { [weak self] in
            self?.onDisconnect?()
            self?.scheduleReconnect()
        }
        connection = bridgeConnection
        bridgeConnection.start(queue: queue)
    }

    private func scheduleReconnect() {
        connection = nil
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }
}

extension BridgeSocketClient: UserInputTransport {
    // Uses queue.sync, same caveat as BridgeServer.currentConnections() --
    // must not be called from `queue` itself (never from inside onMessage,
    // which BridgeConnection delivers there).
    var hasConnectedClients: Bool {
        queue.sync { connection != nil }
    }

    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool {
        queue.sync {
            guard let connection else { return false }
            connection.send(message)
            return true
        }
    }
}
