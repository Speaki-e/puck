//
//  BridgeConnection.swift
//  PetAgent
//
//  F11/socket · owner: Haeyoung Park
//  JSON Lines parsing/serialization, connection lifecycle management
//

import Foundation
import Network

/// Incrementally parses JSON Lines (newline-delimited JSON, protocol repo
/// section 2) from a byte stream that may arrive in arbitrarily-sized chunks.
/// Feed raw bytes via `feed(_:)`; it returns every complete, decodable message
/// found so far and buffers any trailing partial line for the next call.
/// Malformed lines are dropped without breaking subsequent parsing.
struct JSONLinesDecoder {
    private var buffer = Data()
    private let decoder = JSONDecoder()

    mutating func feed(_ data: Data) -> [BridgeMessage] {
        buffer.append(data)

        var messages: [BridgeMessage] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty, let message = try? decoder.decode(BridgeMessage.self, from: lineData) else {
                continue
            }
            messages.append(message)
        }
        return messages
    }
}

/// Wraps a single NWConnection (one workspace client) and handles JSON Lines
/// framing on top of it via JSONLinesDecoder.
final class BridgeConnection {
    private let connection: NWConnection
    private var linesDecoder = JSONLinesDecoder()
    private let encoder = JSONEncoder()

    var onMessage: ((BridgeMessage) -> Void)?
    var onClose: (() -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.onClose?()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    func send(_ message: BridgeMessage) {
        guard var data = try? encoder.encode(message) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for message in self.linesDecoder.feed(data) {
                    self.onMessage?(message)
                }
            }
            if isComplete || error != nil {
                self.onClose?()
                return
            }
            self.receiveNext()
        }
    }
}
