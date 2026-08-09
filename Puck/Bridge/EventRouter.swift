//
//  EventRouter.swift
//  Puck
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

/// The FSM's states, named without reference to their concrete StateHandler
/// instances so EventRouter and the states themselves can request a
/// transition without holding one.
enum StateKind: Equatable, CaseIterable {
    case idle
    case walk
    case climb
    case walkOnTop
    case fall
    case land
    case moveTo
    case point
    case type
    case listen
    case reactClick
    case reactDrag
    /// The twirl after the user finishes petting the pet's head (2026-07-29).
    /// Never reachable from a socket event -- see EventRouter.reaction(for:).
    case spin
    /// F12 (2026-07-29, optional ball-toy interaction): chase a thrown ball,
    /// then kick it away. Never reachable from a socket event -- see
    /// EventRouter.reaction(for:), which has no case producing these.
    case chaseBall
    /// A couple of small pops before the final kick-away (2026-07-29, more
    /// interaction variety), between chaseBall arriving and kickBall.
    case juggleBall
    case kickBall
    /// F3 ceiling-crawling (2026-07-29): climb straight up to the ceiling,
    /// then crawl there upside-down. Reached only from WanderScheduler's
    /// idle roll, never from a socket event.
    case climbToCeiling
    case ceiling
    /// Double-tap "petting" interaction (2026-07-29, byeolki's request for
    /// more interactions). Never reachable from a socket event, same as
    /// chaseBall/kickBall.
    case petting
    /// F13 (2026-07-29): holds still while the Option+Shift+Space client
    /// window is open, same "capture then restore" pattern as Listen (F7).
    /// Never reachable from a socket event.
    case pinned
}

/// The result of routing one BridgeEvent: an optional state transition, an
/// optional extra SFX key (beyond whatever the target state's own name would
/// trigger), optional jump/speech-bubble flourishes, and an optional emotion
/// key (Settings' emotion mapping, 2026-07-29 -- AvatarPlayable.showEmotion).
struct EventReaction: Equatable {
    var stateTransition: StateKind?
    var sfxKey: String?
    var jump: Bool = false
    var bubbleText: String?
    var emotion: String?
}

enum EventRouter {
    /// Maps a protocol 3.2 event to a reaction, per the table in
    /// 02_pet-app.md section 3 F3 ("소켓 이벤트 -> 반응 매핑").
    ///
    /// - Parameter previousCodeEditorPath: the `detail.path` from the most
    ///   recent code_editor tool_call, if any -- kept here as an explicit
    ///   parameter rather than mutable state on this type (a pure decision
    ///   function, per the file header) so the caller (BridgeMessageRouter)
    ///   owns tracking it across calls. Used to detect a path *change*
    ///   ("detail.path 변경 시 짧은 점프") -- the very first code_editor
    ///   event of a session has nothing to compare against, so it never
    ///   jumps on its own.
    static func reaction(for event: BridgeEvent, previousCodeEditorPath: String? = nil) -> EventReaction {
        switch event {
        case .agentThinking:
            return EventReaction(stateTransition: .idle, emotion: "thinking")

        case .textChunk:
            // Chat-rendering data for F13 (2026-07-29), not a pet reaction --
            // no-op here, same as toolResult(ok: true) below.
            return EventReaction()

        case .toolCall(_, let tool, _, let detail):
            // code_editor gets a dedicated typing reaction; every other tool
            // (run_shell, run_applescript, and anything else) points at wherever
            // the action is happening — the "run_shell 계열" row in the table.
            guard tool == "code_editor" else {
                return EventReaction(stateTransition: .point)
            }
            let path = codeEditorPath(from: detail)
            let pathChanged = previousCodeEditorPath != nil && path != nil && path != previousCodeEditorPath
            return EventReaction(stateTransition: .type, jump: pathChanged)

        case .toolResult(_, let ok, _, _, _):
            return ok
                ? EventReaction()
                : EventReaction(stateTransition: .reactClick, sfxKey: "task_fail", emotion: "sad")

        case .awaitApproval:
            return EventReaction(stateTransition: .point, sfxKey: "await_approval", emotion: "thinking")

        case .agentDone(let ok, let summary):
            // Only agent_done(ok=true) is specified; a failed run is already
            // signaled via toolResult(ok=false).
            return ok
                ? EventReaction(sfxKey: "task_success", jump: true, bubbleText: summary, emotion: "happy")
                : EventReaction()
        }
    }

    /// Extracts `detail.path` from a code_editor tool_call (protocol 3.2:
    /// `{"event":"tool_call","tool":"code_editor","detail":{"path":"src/main.ts"}}`).
    /// Exposed so BridgeMessageRouter can track it across calls without
    /// duplicating the JSONValue destructuring.
    static func codeEditorPath(from detail: JSONValue?) -> String? {
        guard case .object(let fields)? = detail, case .string(let path)? = fields["path"] else { return nil }
        return path
    }
}
