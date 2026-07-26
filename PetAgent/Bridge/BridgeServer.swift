//
//  BridgeServer.swift
//  PetAgent
//
//  F11/socket · owner: Haeyoung Park
//  Network.framework NWListener(UDS) at ~/Library/Application Support/PetAgent/bridge.sock
//

import Foundation
import Network

/// Runs the JSON Lines Unix-domain-socket server pet-app exposes to workspace
/// (protocol repo section 2: "서버: pet-app (NWListener)"). workspace connects
/// as a client and reconnects with exponential backoff on its own; pet-app's
/// job is just to accept connections and stay a pure pet when none are open.
final class BridgeServer {
    static let defaultSocketURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PetAgent", isDirectory: true).appendingPathComponent("bridge.sock")
    }()

    private(set) var connections: [BridgeConnection] = []
    private var listener: NWListener?
    private let socketURL: URL
    private let queue = DispatchQueue(label: "PetAgent.BridgeServer")

    /// Called for every message from any connected client, along with which
    /// connection it came from (so a reply can be sent back to that client).
    var onMessage: ((BridgeMessage, BridgeConnection) -> Void)?

    init(socketURL: URL = BridgeServer.defaultSocketURL) {
        self.socketURL = socketURL
    }

    func start() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: socketURL) // stale socket file from a previous run

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketURL.path)

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ nwConnection: NWConnection) {
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
}
