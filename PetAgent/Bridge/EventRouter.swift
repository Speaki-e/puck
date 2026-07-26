//
//  EventRouter.swift
//  PetAgent
//
//  F3/socket · owner: Haeyoung Park
//  Maps protocol 3.2 state events to FSM/SFX reactions
//
//  This is a pure decision function — it does not touch CharacterController or
//  SFXTriggering directly. Wiring `reaction(for:)`'s output to real, shared
//  state instances happens at app-bootstrap time (once CharacterController is
//  constructed with the FSM's long-lived state set); creating a fresh state
//  instance per event here would break CharacterController's same-state no-op
//  check and reset per-state timers/data on every repeated event.

/// A subset of FSM states EventRouter can request a transition into. Kept
/// separate from concrete StateHandler instances for testability.
enum StateKind: Equatable {
    case idle
    case type
    case point
    case reactClick
}

/// The result of routing one BridgeEvent: an optional state transition, an
/// optional extra SFX key (beyond whatever the target state's own name would
/// trigger), and optional jump/speech-bubble flourishes.
struct EventReaction: Equatable {
    var stateTransition: StateKind?
    var sfxKey: String?
    var jump: Bool = false
    var bubbleText: String?
}

enum EventRouter {
    /// Maps a protocol 3.2 event to a reaction, per the table in
    /// 02_pet-app.md section 3 F3 ("소켓 이벤트 -> 반응 매핑").
    static func reaction(for event: BridgeEvent) -> EventReaction {
        switch event {
        case .agentThinking:
            return EventReaction(stateTransition: .idle)

        case .toolCall(let tool, _):
            // code_editor gets a dedicated typing reaction; every other tool
            // (run_shell, run_applescript, and anything else) points at wherever
            // the action is happening — the "run_shell 계열" row in the table.
            return EventReaction(stateTransition: tool == "code_editor" ? .type : .point)

        case .toolResult(let ok):
            return ok ? EventReaction() : EventReaction(stateTransition: .reactClick, sfxKey: "task_fail")

        case .awaitApproval:
            return EventReaction(stateTransition: .point, sfxKey: "await_approval")

        case .agentDone(let ok, let summary):
            // Only agent_done(ok=true) is specified; a failed run is already
            // signaled via toolResult(ok=false).
            return ok ? EventReaction(sfxKey: "task_success", jump: true, bubbleText: summary) : EventReaction()
        }
    }
}
