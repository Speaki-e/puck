//
//  BridgeServerTests.swift
//  PetAgent
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  End-to-end test over a real Unix domain socket (no mocks): starts a
//  BridgeServer on a temp path, connects a bare NWConnection client, and
//  verifies messages flow both ways. protocol/01_protocol.md section 2.
//

import XCTest
import Network
@testable import PetAgent

final class BridgeServerTests: XCTestCase {
    private var socketURL: URL!
    private var server: BridgeServer!

    override func setUpWithError() throws {
        socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("bridge.sock")
        server = BridgeServer(socketURL: socketURL)
        try server.start()
    }

    override func tearDown() {
        server.stop()
        try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
    }

    private func makeClient() -> NWConnection {
        NWConnection(to: .unix(path: socketURL.path), using: .tcp)
    }

    func test_serverReceivesMessageSentByClient() {
        let received = expectation(description: "server received the client's message")
        server.onMessage = { message, _ in
            guard case .userInput(let input) = message else { return }
            XCTAssertEqual(input.text, "hello")
            received.fulfill()
        }

        let client = makeClient()
        client.stateUpdateHandler = { state in
            if case .ready = state {
                var data = try! JSONEncoder().encode(BridgeMessage.userInput(UserInput(text: "hello", source: .text)))
                data.append(0x0A)
                client.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        client.start(queue: .main)

        wait(for: [received], timeout: 5)
        client.cancel()
    }

    func test_clientReceivesReplySentThroughAcceptedConnection() {
        let clientReceived = expectation(description: "client received the server's reply")
        server.onMessage = { _, connection in
            connection.send(.toolResult(ToolResult(id: "t1", ok: true, data: nil, error: nil)))
        }

        let client = makeClient()
        var buffer = Data()
        client.stateUpdateHandler = { state in
            if case .ready = state {
                var data = try! JSONEncoder().encode(BridgeMessage.userInput(UserInput(text: "ping", source: .text)))
                data.append(0x0A)
                client.send(content: data, completion: .contentProcessed { _ in })
            }
        }

        func receiveLoop() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                if let data { buffer.append(data) }
                if let message = try? JSONDecoder().decode(BridgeMessage.self, from: buffer.dropLast()),
                    case .toolResult(let result) = message
                {
                    XCTAssertTrue(result.ok)
                    clientReceived.fulfill()
                    return
                }
                receiveLoop()
            }
        }
        receiveLoop()
        client.start(queue: .main)

        wait(for: [clientReceived], timeout: 5)
        client.cancel()
    }
}
