//
//  BridgeSocketClientTests.swift
//  Puck
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  PuckClient's own bridge.sock client (2026-07-30) -- connects as role
//  "gui" (protocol 3.7) and doubles as UserInputSender's UserInputTransport.
//

import XCTest
@testable import Puck

final class BridgeSocketClientTests: XCTestCase {
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

    /// BridgeServer intercepts client_hello internally (never forwards it to
    /// onMessage) -- onGUIPresenceChanged firing true is the observable proof
    /// that the client actually sent role .gui and the server accepted it.
    func test_start_sendsClientHelloWithGUIRole() {
        let presenceChanged = expectation(description: "server saw a gui client connect")
        server.onGUIPresenceChanged = { present in
            guard present else { return }
            presenceChanged.fulfill()
        }

        let client = BridgeSocketClient(socketURL: socketURL)
        client.start()

        wait(for: [presenceChanged], timeout: 5)
    }

    func test_hasConnectedClients_becomesTrueAfterConnecting() {
        let client = BridgeSocketClient(socketURL: socketURL)
        XCTAssertFalse(client.hasConnectedClients)

        let ready = expectation(description: "client connected")
        pollUntilTrue(timeout: 5, expectation: ready) { client.hasConnectedClients }
        client.start()
        wait(for: [ready], timeout: 6)
    }

    func test_broadcast_deliversToTheServer() {
        let delivered = expectation(description: "server received the broadcast message")
        server.onMessage = { message, _ in
            guard case .userInput(let input) = message else { return }
            XCTAssertEqual(input.text, "hi")
            delivered.fulfill()
        }

        let client = BridgeSocketClient(socketURL: socketURL)
        let ready = expectation(description: "client connected")
        pollUntilTrue(timeout: 5, expectation: ready) { client.hasConnectedClients }
        client.start()
        wait(for: [ready], timeout: 6)

        client.broadcast(.userInput(UserInput(text: "hi", source: .text)))
        wait(for: [delivered], timeout: 5)
    }

    func test_onMessage_firesForMessagesRelayedByTheServer() {
        let client = BridgeSocketClient(socketURL: socketURL)
        let received = expectation(description: "client received the relayed event")
        client.onMessage = { message in
            guard case .event(let event, _, _) = message else { return }
            XCTAssertEqual(event, .agentThinking)
            received.fulfill()
        }

        let ready = expectation(description: "client connected")
        pollUntilTrue(timeout: 5, expectation: ready) { client.hasConnectedClients }
        client.start()
        wait(for: [ready], timeout: 6)

        server.onMessage = { _, connection in
            connection.send(.event(.agentThinking, workspaceId: "w1", sessionId: "s1"))
        }
        client.broadcast(.userInput(UserInput(text: "trigger", source: .text)))

        wait(for: [received], timeout: 5)
    }

    private func pollUntilTrue(timeout: TimeInterval, expectation: XCTestExpectation, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() {
                expectation.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
    }
}
