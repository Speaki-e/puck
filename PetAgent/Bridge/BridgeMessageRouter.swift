//
//  BridgeMessageRouter.swift
//  PetAgent
//
//  F11/socket · owner: 박해영 (Haeyoung Park)
//  Routes an incoming BridgeMessage to tool execution or an FSM/SFX reaction,
//  hopping onto the main thread first.
//
//  BridgeServer delivers messages on its own background queue, but everything
//  downstream of here is main-thread-only:
//    - EventRouter reactions drive CharacterController -> USDZAvatar, i.e.
//      RealityKit entity mutation (addChild/removeFromParent/playAnimation),
//      which is not safe off the main thread.
//    - pet-app-executor handlers read NSWorkspace and WindowListWatcher.windows,
//      the latter being mutated by a 10Hz timer that runs on main.
//  Handlers that do genuinely slow work (RunShellHandler, RunAppleScriptHandler)
//  hop onto their own background queue internally, so this does not park long
//  work on main.
//

import Foundation

final class BridgeMessageRouter {
    private let toolExecutor: ToolExecutor
    private let dispatchToMain: (@escaping () -> Void) -> Void

    /// Emitted for protocol 3.2 status events, already on the main thread.
    var onEventReaction: ((EventReaction) -> Void)?

    /// - Parameter dispatchToMain: injected so tests can observe the hop.
    ///   Defaults to an async hop to the main queue; it stays async even when
    ///   already on main so ordering is identical from every caller.
    init(
        toolExecutor: ToolExecutor,
        dispatchToMain: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }
    ) {
        self.toolExecutor = toolExecutor
        self.dispatchToMain = dispatchToMain
    }

    /// - Parameter reply: how to send a message back to the client this one
    ///   arrived on. Kept as a closure rather than a BridgeConnection so this
    ///   type stays independent of Network.framework (and testable without a
    ///   live socket).
    func handle(_ message: BridgeMessage, reply: @escaping (BridgeMessage) -> Void) {
        switch message {
        case .toolDispatch(let dispatch):
            dispatchToMain { [toolExecutor] in
                toolExecutor.dispatch(dispatch) { result in
                    reply(.toolResult(result))
                }
            }

        case .event(let event):
            let reaction = EventRouter.reaction(for: event)
            dispatchToMain { [weak self] in
                self?.onEventReaction?(reaction)
            }

        case .toolResult, .userInput:
            break // pet-app only ever sends these, never receives them
        }
    }
}
