//
//  UserInputSender.swift
//  PetAgent
//
//  F6/F7 · owner: 박해영 (Haeyoung Park)
//  Sends protocol 3.3 user_input, and tells the caller when it couldn't.
//
//  AppDelegate used to cache the last BridgeConnection handed to it by
//  BridgeServer.onMessage and never clear it, so once workspace disconnected
//  the app still believed it had a client: it wrote into a cancelled socket
//  and the input vanished with no feedback. F6 requires a "워크스페이스
//  꺼져있음" bubble in exactly that case, which needs the send to report
//  failure rather than pretend.
//

import Foundation

/// What pet-app needs from the socket layer in order to send user input.
/// Kept narrow so the decision is testable without Network.framework.
protocol UserInputTransport: AnyObject {
    /// Live state, not a remembered one — a client that disconnected must
    /// stop counting immediately.
    var hasConnectedClients: Bool { get }
    func broadcast(_ message: BridgeMessage)
}

enum UserInputDelivery: Equatable {
    case sent
    /// Nothing is listening: the socket server never started, or workspace
    /// is not connected (or has since gone away).
    case workspaceDisconnected
}

final class UserInputSender {
    private let transport: () -> UserInputTransport?

    /// - Parameter transport: resolved per send, so connection state is read
    ///   fresh every time instead of captured once.
    init(transport: @escaping () -> UserInputTransport?) {
        self.transport = transport
    }

    @discardableResult
    func send(text: String, source: UserInput.Source) -> UserInputDelivery {
        guard let transport = transport(), transport.hasConnectedClients else {
            return .workspaceDisconnected
        }
        transport.broadcast(.userInput(UserInput(text: text, source: source)))
        return .sent
    }
}
