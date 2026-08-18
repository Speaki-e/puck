//
//  ChatSession.swift
//  Puck
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
    /// locally the moment the store sends, rather than folding it from
    /// an event like every other case here.
    case userMessage(id: UUID, text: String)
    case assistantText(id: UUID, text: String)
    case toolCall(id: String, tool: String, args: JSONValue?)
    case toolResult(id: String, ok: Bool, data: JSONValue?, error: ToolErrorCode?, detail: String?)
    case approvalRequested(id: UUID, approvalId: String, summary: String)
    case done(id: UUID, ok: Bool, summary: String)
}

extension ChatTimelineEntry {
    /// Whether this row begins a new exchange. Only what a person said, or the
    /// agent's own prose answering it, starts one; a tool call and its outcome
    /// belong to the turn that produced them.
    var startsNewTurn: Bool {
        switch self {
        case .userMessage, .assistantText: return true
        case .toolCall, .toolResult, .approvalRequested, .done: return false
        }
    }
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
        // Was a fixed "done" on the assumption that agent_done happens once
        // per session. It doesn't: a session takes as many prompts as the
        // user types, and every run ends with one. Two rows sharing an id in
        // the transcript's ForEach is undefined behaviour -- what it did in
        // practice was throw the scroll position to the top of the list the
        // moment a second run finished.
        case .done(let id, _, _): return id
        }
    }
}

/// One approval the agent is blocked on. Identified by the protocol's own
/// `approval_id`: that is the id the answer has to be addressed to, and the
/// only thing that ties a banner to the request waiting behind it.
struct PendingApproval: Equatable, Identifiable {
    let approvalId: String
    let summary: String

    var id: String { approvalId }
}

/// What an approval banner can do right now.
enum ApprovalState: Equatable {
    /// The one the buttons act on -- the oldest request still unanswered.
    case actionable
    /// Asked for, but an older request is still in front of it.
    case queued
    /// Answered, or abandoned when the run ended.
    case resolved
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
    /// Every approval still waiting on the user, oldest first.
    ///
    /// A queue rather than a single slot: the coding agent batches parallel
    /// tool calls, so two `session/request_permission` calls can be in flight
    /// at once. With one slot the second overwrote the first, the UI could
    /// then only ever produce an answer for the second, and the first request's
    /// caller waited on an answer that could no longer be given -- which stalls
    /// the agent for the whole tool timeout. Answered oldest-first so the two
    /// buttons always mean one unambiguous request.
    @Published private(set) var pendingApprovals: [PendingApproval] = []
    @Published private(set) var isRunning = false

    /// The request the approval buttons answer, or nil when none is waiting.
    var pendingApproval: PendingApproval? { pendingApprovals.first }

    /// When this session last saw any agent event. Drives the sidebar's relative
    /// time ("12분", "어제") -- nothing else in the app tracked time before v3.
    @Published private(set) var lastActivityAt: Date?

    /// Outcome of the most recent completed run, or nil if none has completed.
    /// Derived from the timeline rather than stored: `.done` already carries `ok`,
    /// and a second copy could disagree with it.
    var lastRunOk: Bool? {
        for entry in timeline.reversed() {
            if case .done(_, let ok, _) = entry { return ok }
        }
        return nil
    }

    init(id: String, workspaceId: String, title: String, origin: SessionOrigin) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.origin = origin
    }

    /// Local echo of the user's own send -- called by ClientWindowStore, not
    /// folded from a BridgeEvent (protocol never sends the user's own text
    /// back).
    func appendUserMessage(_ text: String) {
        timeline.append(.userMessage(id: UUID(), text: text))
    }

    /// The send landed, so the agent owes an answer -- shown as the "생각 중"
    /// row until the first text_chunk replaces it -- the user should see that
    /// the agent is working while it generates a reply, not a blank gap.
    ///
    /// Set here rather than waiting for agent_thinking: that event is produced
    /// by the agent, put on the socket, and relayed back to this app, so the
    /// window would sit with no feedback for the whole round trip -- and if
    /// the agent's very first act is a slow model call, that is the exact
    /// stretch the user is staring at.
    func markWaitingForAgent() {
        isRunning = true
    }

    /// Folds one BridgeEvent into the timeline. Caller (ClientWindowStore) is
    /// responsible for routing the event to the right session by
    /// workspace_id/session_id first -- this type has no notion of "is this
    /// event mine".
    func apply(_ event: BridgeEvent) {
        lastActivityAt = Date()
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
            // Re-broadcast of an id already queued is not a second request.
            if !pendingApprovals.contains(where: { $0.approvalId == approvalId }) {
                pendingApprovals.append(PendingApproval(approvalId: approvalId, summary: summary))
            }
            timeline.append(.approvalRequested(id: UUID(), approvalId: approvalId, summary: summary))

        case .agentDone(let ok, let summary):
            isRunning = false
            // The run is over, so nothing is waiting on these any more. The
            // side holding the requests fails whatever is left (AgentHost),
            // so no answer is silently dropped here.
            pendingApprovals.removeAll()
            timeline.append(.done(id: UUID(), ok: ok, summary: summary))
        }
    }

    /// The user answered this request; it stops being pending and the next one
    /// in line becomes actionable. Unknown ids are ignored -- an answer that
    /// crossed with `agent_done` is not an error.
    func resolveApproval(approvalId: String) {
        pendingApprovals.removeAll { $0.approvalId == approvalId }
    }

    func approvalState(for approvalId: String) -> ApprovalState {
        guard let index = pendingApprovals.firstIndex(where: { $0.approvalId == approvalId }) else {
            return .resolved
        }
        return index == 0 ? .actionable : .queued
    }
}
