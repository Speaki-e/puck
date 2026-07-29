//
//  BridgeSocketClient.swift
//  PetAgent
//
//  F13/socket · owner: 박해영 (Haeyoung Park)
//  PetAgentClient's own connection to bridge.sock (2026-07-30) -- unlike
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

    private let socketURL: URL
    private let queue = DispatchQueue(label: "PetAgentClient.BridgeSocketClient")
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
