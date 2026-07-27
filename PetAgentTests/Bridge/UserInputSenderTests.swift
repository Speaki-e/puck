//
//  UserInputSenderTests.swift
//  PetAgent
//
//  F6/F7 test · owner: 박해영 (Haeyoung Park)
//  AppDelegate cached the last BridgeConnection it saw and never cleared it,
//  so after workspace disconnected the app still believed it was connected,
//  sent user_input into a dead socket, and silently dropped it — the
//  "워크스페이스 꺼져있음" bubble F6 calls for could never appear. Delivery is
//  now decided against live connection state and reported back to the caller.
//

import XCTest
@testable import PetAgent

private final class StubTransport: UserInputTransport {
    var hasConnectedClients: Bool
    private(set) var broadcasted: [BridgeMessage] = []

    init(hasConnectedClients: Bool) {
        self.hasConnectedClients = hasConnectedClients
    }

    func broadcast(_ message: BridgeMessage) {
        broadcasted.append(message)
    }
}

final class UserInputSenderTests: XCTestCase {
    func test_withConnectedClient_broadcastsUserInputAndReportsSent() {
        let transport = StubTransport(hasConnectedClients: true)
        let sender = UserInputSender { transport }

        let delivery = sender.send(text: "테스트 돌려줘", source: .voice)

        XCTAssertEqual(delivery, .sent)
        XCTAssertEqual(
            transport.broadcasted,
            [.userInput(UserInput(text: "테스트 돌려줘", source: .voice))]
        )
    }

    func test_withNoConnectedClient_reportsDisconnectedAndSendsNothing() {
        let transport = StubTransport(hasConnectedClients: false)
        let sender = UserInputSender { transport }

        let delivery = sender.send(text: "README 열어줘", source: .text)

        XCTAssertEqual(delivery, .workspaceDisconnected)
        XCTAssertTrue(transport.broadcasted.isEmpty, "must not write into a socket with no client")
    }

    /// BridgeServer is nil when it failed to start at all (independence
    /// principle: pet-app still runs as a pure pet). That is the same
    /// user-visible situation as no client being connected.
    func test_withNoTransportAtAll_reportsDisconnected() {
        let sender = UserInputSender { nil }

        XCTAssertEqual(sender.send(text: "안녕", source: .text), .workspaceDisconnected)
    }

    /// The transport is consulted per send, not captured once — a client that
    /// disconnects between two sends must flip the result.
    func test_transportStateIsReReadOnEverySend() {
        let transport = StubTransport(hasConnectedClients: true)
        let sender = UserInputSender { transport }

        XCTAssertEqual(sender.send(text: "first", source: .text), .sent)

        transport.hasConnectedClients = false
        XCTAssertEqual(sender.send(text: "second", source: .text), .workspaceDisconnected)
        XCTAssertEqual(transport.broadcasted.count, 1, "the second send must not have gone out")
    }
}
