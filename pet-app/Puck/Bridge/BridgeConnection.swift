//
//  BridgeConnection.swift
//  Puck
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
/// Malformed lines are dropped (counted in `droppedLineCount`) without
/// breaking subsequent parsing. A line that never terminates and exceeds
/// `maxLineLength` is treated as abusive: the buffer is cleared and
/// `didOverflow` is reported so the caller can close the connection, instead
/// of letting a buggy/hostile client grow this buffer forever on a
/// long-lived, menu-bar-resident process.
struct JSONLinesDecoder {
    struct FeedResult {
        let messages: [BridgeMessage]
        let didOverflow: Bool
        /// How many lines this specific `feed()` call dropped -- distinct
        /// from `droppedLineCount`'s running total, so a caller can react
        /// (e.g. log) to a fresh drop without diffing the total itself.
        let droppedThisCall: Int
    }

    private var buffer = Data()
    private let decoder = JSONDecoder()
    private let maxLineLength: Int
    private(set) var droppedLineCount = 0

    init(maxLineLength: Int = 1_048_576) {
        self.maxLineLength = maxLineLength
    }

    mutating func feed(_ data: Data) -> FeedResult {
        buffer.append(data)

        var messages: [BridgeMessage] = []
        var droppedThisCall = 0
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else { continue }
            if let message = try? decoder.decode(BridgeMessage.self, from: lineData) {
                messages.append(message)
            } else {
                droppedLineCount += 1
                droppedThisCall += 1
            }
        }

        guard buffer.count <= maxLineLength else {
            buffer.removeAll()
            return FeedResult(messages: messages, didOverflow: true, droppedThisCall: droppedThisCall)
        }
        return FeedResult(messages: messages, didOverflow: false, droppedThisCall: droppedThisCall)
    }
}

enum BridgeConnectionError: Error, Equatable {
    case encodingFailed
}

/// Wraps a single NWConnection (one workspace client) and handles JSON Lines
/// framing on top of it via JSONLinesDecoder.
final class BridgeConnection {
    private let connection: NWConnection
    private var linesDecoder = JSONLinesDecoder()
    private var hasClosed = false

    /// Set once, from this connection's client_hello (protocol 3.7) --
    /// nil until then. BridgeServer uses it to decide which connections a
    /// given message relays to (ClientRelay.targetRole).
    var role: ClientRole?

    var onMessage: ((BridgeMessage) -> Void)?
    /// Fires once the wrapped connection reaches .ready -- PuckClient's
    /// own outbound connection (2026-07-30) needs this to know when it's
    /// safe to send client_hello, which BridgeServer's accepted (server-side)
    /// connections never needed since they're only handed to onMessage/
    /// onClose once already open.
    var onReady: (() -> Void)?
    /// Fires exactly once per connection, regardless of whether the close was
    /// observed via stateUpdateHandler or the receive completion handler.
    var onClose: (() -> Void)?
    /// Fires when a message fails to encode, or the transport itself reports
    /// a send error — previously both were silently swallowed, leaving the
    /// agent side to time out with no diagnostic on our end.
    var onSendError: ((Error) -> Void)?
    /// Fires once per line JSONLinesDecoder drops -- droppedLineCount was
    /// previously only ever read by tests, so protocol drift or a hostile
    /// connection produced zero operational signal (found via review); the
    /// only symptom was a tool_result that never arrived, indistinguishable
    /// from "the tool is just slow" until ToolExecutor's own timeout.
    var onMalformedLine: (() -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onReady?()
            case .cancelled, .failed:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    func send(_ message: BridgeMessage) {
        // A local encoder, not a shared stored property: send() is called
        // from whatever queue each ToolHandler completes on (several hop to
        // their own background queue), so two in-flight tool_results on the
        // same connection could call encode() concurrently on one instance.
        guard var data = try? JSONEncoder().encode(message) else {
            onSendError?(BridgeConnectionError.encodingFailed)
            return
        }
        data.append(0x0A)
        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.onSendError?(error)
                }
            }
        )
    }

    func cancel() {
        connection.cancel()
    }

    private func close() {
        guard !hasClosed else { return }
        hasClosed = true
        onClose?()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let result = self.linesDecoder.feed(data)
                for message in result.messages {
                    self.onMessage?(message)
                }
                for _ in 0..<result.droppedThisCall {
                    self.onMalformedLine?()
                }
                if result.didOverflow {
                    self.cancel() // triggers stateUpdateHandler -> .cancelled -> close()
                    return
                }
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receiveNext()
        }
    }
}
