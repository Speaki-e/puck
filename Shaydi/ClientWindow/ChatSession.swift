//
//  ChatSession.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  One chat session's rendered timeline, built by folding the same
//  BridgeEvent stream EventRouter reads for pet reactions (plan/01_protocol.md
//  3.2) into something plan/02_pet-app.md F13 can render: streaming assistant
//  text, a tool-call/result timeline correlated by id, and an approval banner.
//

import Foundation

/// One row in a chat session's timeline. toolCall/toolResult reuse the
/// protocol's own tool_use `id` as their identity (already unique per
/// session); the rest mint their own, since nothing else in the wire format
/// gives them one.
enum ChatTimelineEntry: Equatable {
    /// The user's own sent message -- BridgeEvent never carries this (it's
    /// workspace -> pet-app only), so ChatSession.appendUserMessage mints it
    /// locally the moment the chat view sends, rather than folding it from
    /// an event like every other case here.
    case userMessage(id: UUID, text: String)
    case assistantText(id: UUID, text: String)
    case toolCall(id: String, tool: String, args: JSONValue?)
    case toolResult(id: String, ok: Bool, data: JSONValue?, error: String?, detail: String?)
    case approvalRequested(id: UUID, approvalId: String, summary: String)
    case done(ok: Bool, summary: String)
}

extension ChatTimelineEntry: Identifiable {
    // toolCall and toolResult share the same underlying tool_use id (that's
    // the point -- it's how a view correlates them), so their *displayed
    // entry* ids need distinct prefixes or the two rows collide.
    var id: AnyHashable {
        switch self {
        case .userMessage(let id, _): return id
        case .assistantText(let id, _): return id
        case .toolCall(let id, _, _): return "call:\(id)"
        case .toolResult(let id, _, _, _, _): return "result:\(id)"
        case .approvalRequested(let id, _, _): return id
        // done is emitted at most once per session (agent_done ends the run),
        // so a fixed identity is fine -- there's never a second one to collide with.
        case .done: return "done"
        }
    }
}

/// One chat session under a workspace. `id`/`workspaceId` are the protocol's
/// own ids (both "default" for the always-present casual session -- see
/// ClientWindowStore's composite-key note on why that's not a collision).
final class ChatSession: ObservableObject, Identifiable {
    let id: String
    let workspaceId: String
    let origin: SessionOrigin
    @Published var title: String
    @Published private(set) var timeline: [ChatTimelineEntry] = []
    @Published private(set) var pendingApproval: (approvalId: String, summary: String)?
    @Published private(set) var isRunning = false

    init(id: String, workspaceId: String, title: String, origin: SessionOrigin) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.origin = origin
    }

    /// Local echo of the user's own send -- called by ChatView, not folded
    /// from a BridgeEvent (protocol never sends the user's own text back).
    func appendUserMessage(_ text: String) {
        timeline.append(.userMessage(id: UUID(), text: text))
    }

    /// Folds one BridgeEvent into the timeline. Caller (ClientWindowStore) is
    /// responsible for routing the event to the right session by
    /// workspace_id/session_id first -- this type has no notion of "is this
    /// event mine".
    func apply(_ event: BridgeEvent) {
        switch event {
        case .agentThinking:
            isRunning = true

        case .textChunk(let text):
            isRunning = true
            if case .assistantText(let entryId, let existing) = timeline.last {
                timeline[timeline.count - 1] = .assistantText(id: entryId, text: existing + text)
            } else {
                timeline.append(.assistantText(id: UUID(), text: text))
            }

        case .toolCall(let id, let tool, let args, _):
            // `detail` (curated pet-reaction summary) is intentionally dropped
            // here -- the chat view shows the tool's real args instead.
            timeline.append(.toolCall(id: id, tool: tool, args: args))

        case .toolResult(let id, let ok, let data, let error, let detail):
            timeline.append(.toolResult(id: id, ok: ok, data: data, error: error, detail: detail))

        case .awaitApproval(let summary, let approvalId):
            pendingApproval = (approvalId, summary)
            timeline.append(.approvalRequested(id: UUID(), approvalId: approvalId, summary: summary))

        case .agentDone(let ok, let summary):
            isRunning = false
            pendingApproval = nil
            timeline.append(.done(ok: ok, summary: summary))
        }
    }
}
