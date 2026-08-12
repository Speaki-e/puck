//
//  ClientChatBridgeMessages.swift
//  Puck
//
//  F13 chat rebuild · owner: 박해영 (Haeyoung Park)
//  The local JS<->Swift contract for ClientChatWebView (chat-web/src/lib/
//  bridge-types.ts is the JS-side mirror -- keep both in sync by hand, this
//  is not the bridge.sock wire protocol and doesn't change it). Swift pushes
//  state via webView.evaluateJavaScript("window.PuckChatBridge.receive(...)");
//  JS posts actions via window.webkit.messageHandlers.puckChat.postMessage(...).
//

import Foundation

// MARK: - Outbound (Swift -> JS) payload shapes

struct WorkspaceJSON: Encodable {
    let id: String
    let name: String
    let projectPath: String?
    let canOpenEditor: Bool

    init(_ workspace: ClientWorkspace) {
        id = workspace.id
        name = workspace.name
        projectPath = workspace.projectPath
        canOpenEditor = workspace.canOpenEditor
    }
}

struct SessionSummaryJSON: Encodable {
    let id: String
    let workspaceId: String
    let title: String
    let isRunning: Bool

    init(_ session: ChatSession) {
        id = session.id
        workspaceId = session.workspaceId
        title = session.title
        isRunning = session.isRunning
    }
}

struct PendingApprovalJSON: Encodable {
    let approvalId: String
    let summary: String
}

/// Flat shape covering every ChatTimelineEntry case -- irrelevant fields are
/// nil and simply absent from the encoded JSON (encoder skips nil Optionals).
/// JS narrows on `kind`, same as Swift narrows on the enum case.
struct TimelineEntryJSON: Encodable {
    let kind: String
    let id: String
    var text: String?
    var tool: String?
    var args: JSONValue?
    var ok: Bool?
    var data: JSONValue?
    var error: ToolErrorCode?
    var detail: String?
    var approvalId: String?
    var summary: String?

    init(_ entry: ChatTimelineEntry) {
        switch entry {
        case .userMessage(let id, let text):
            kind = "userMessage"; self.id = id.uuidString; self.text = text
        case .assistantText(let id, let text):
            kind = "assistantText"; self.id = id.uuidString; self.text = text
        case .toolCall(let id, let tool, let args):
            kind = "toolCall"; self.id = id; self.tool = tool; self.args = args
        case .toolResult(let id, let ok, let data, let error, let detail):
            kind = "toolResult"; self.id = id; self.ok = ok; self.data = data; self.error = error; self.detail = detail
        case .approvalRequested(let id, let approvalId, let summary):
            kind = "approvalRequested"; self.id = id.uuidString; self.approvalId = approvalId; self.summary = summary
        case .done(let id, let ok, let summary):
            kind = "done"; self.id = id.uuidString; self.ok = ok; self.summary = summary
        }
    }
}

struct SessionStateJSON: Encodable {
    let id: String
    let workspaceId: String
    let title: String
    let timeline: [TimelineEntryJSON]
    let isRunning: Bool
    let pendingApproval: PendingApprovalJSON?

    init(_ session: ChatSession) {
        id = session.id
        workspaceId = session.workspaceId
        title = session.title
        timeline = session.timeline.map(TimelineEntryJSON.init)
        isRunning = session.isRunning
        pendingApproval = session.pendingApproval.map { PendingApprovalJSON(approvalId: $0.approvalId, summary: $0.summary) }
    }
}

struct HydratePayload: Encodable {
    let themeStyle: String
    let workspaces: [WorkspaceJSON]
    let activeWorkspaceId: String
    let activeSessionId: String
    let sessionsByWorkspace: [String: [SessionSummaryJSON]]
    let activeSession: SessionStateJSON?
    let editorOpen: Bool
}

struct BridgeOutboundEnvelope<Payload: Encodable>: Encodable {
    let type: String
    let payload: Payload
}

struct WorkspacesPayload: Encodable {
    let workspaces: [WorkspaceJSON]
    let activeWorkspaceId: String
}

struct SessionsPayload: Encodable {
    let workspaceId: String
    let sessions: [SessionSummaryJSON]
}

struct ActiveSessionPayload: Encodable {
    let session: SessionStateJSON?
}

struct TimelineAppendPayload: Encodable {
    let workspaceId: String
    let sessionId: String
    let entry: TimelineEntryJSON
}

struct TextChunkPayload: Encodable {
    let workspaceId: String
    let sessionId: String
    let entryId: String
    let delta: String
    let append: Bool
}

struct RunningChangedPayload: Encodable {
    let workspaceId: String
    let sessionId: String
    let isRunning: Bool
}

struct PendingApprovalChangedPayload: Encodable {
    let workspaceId: String
    let sessionId: String
    let approval: PendingApprovalJSON?
}

struct EditorOpenPayload: Encodable {
    let isOpen: Bool
    let canOpen: Bool
}

struct ProjectFolderChosenPayload: Encodable {
    let path: String?
}

// MARK: - Inbound (JS -> Swift) payload shapes

/// First decode pass: just the discriminant, so the second pass can pick the
/// right payload type. Mirrors the pattern openai-code-editor.ts-style two-
/// stage parsing elsewhere in this codebase's JSON handling.
private struct TypeOnlyEnvelope: Decodable {
    let type: String
}

private struct BridgeInboundEnvelope<Payload: Decodable>: Decodable {
    let type: String
    let payload: Payload
}

private struct EmptyPayload: Decodable {}

struct SendMessagePayload: Decodable {
    let workspaceId: String
    let sessionId: String
    let text: String
}

struct NewSessionPayload: Decodable {
    let workspaceId: String
    let title: String
}

struct NewWorkspacePayload: Decodable {
    let name: String
    let projectPath: String?
}

struct SwitchWorkspacePayload: Decodable {
    let workspaceId: String
}

struct SwitchSessionPayload: Decodable {
    let workspaceId: String
    let sessionId: String
}

struct RespondApprovalPayload: Decodable {
    let workspaceId: String
    let sessionId: String
    let approvalId: String
    let approved: Bool
}

struct CancelRunPayload: Decodable {
    let workspaceId: String
    let sessionId: String
}

/// The decoded shape of one action posted from JS -- ClientChatBridge
/// switches on this to call the matching ClientWindowStore/ChatSession
/// method. `raw` (message.body re-serialized to Data) is decoded twice: once
/// for the discriminant, once for the typed payload once it's known.
enum ChatBridgeAction {
    case ready
    case sendMessage(SendMessagePayload)
    case newSession(NewSessionPayload)
    case newWorkspace(NewWorkspacePayload)
    case chooseProjectFolder
    case switchWorkspace(SwitchWorkspacePayload)
    case switchSession(SwitchSessionPayload)
    case respondApproval(RespondApprovalPayload)
    case cancelRun(CancelRunPayload)
    case toggleEditor
    case openSettings

    static func decode(from data: Data) throws -> ChatBridgeAction? {
        let typeOnly = try JSONDecoder().decode(TypeOnlyEnvelope.self, from: data)
        let decoder = JSONDecoder()
        switch typeOnly.type {
        case "action:ready":
            return .ready
        case "action:sendMessage":
            return .sendMessage(try decoder.decode(BridgeInboundEnvelope<SendMessagePayload>.self, from: data).payload)
        case "action:newSession":
            return .newSession(try decoder.decode(BridgeInboundEnvelope<NewSessionPayload>.self, from: data).payload)
        case "action:newWorkspace":
            return .newWorkspace(try decoder.decode(BridgeInboundEnvelope<NewWorkspacePayload>.self, from: data).payload)
        case "action:chooseProjectFolder":
            return .chooseProjectFolder
        case "action:switchWorkspace":
            return .switchWorkspace(try decoder.decode(BridgeInboundEnvelope<SwitchWorkspacePayload>.self, from: data).payload)
        case "action:switchSession":
            return .switchSession(try decoder.decode(BridgeInboundEnvelope<SwitchSessionPayload>.self, from: data).payload)
        case "action:respondApproval":
            return .respondApproval(try decoder.decode(BridgeInboundEnvelope<RespondApprovalPayload>.self, from: data).payload)
        case "action:cancelRun":
            return .cancelRun(try decoder.decode(BridgeInboundEnvelope<CancelRunPayload>.self, from: data).payload)
        case "action:toggleEditor":
            return .toggleEditor
        case "action:openSettings":
            return .openSettings
        default:
            return nil
        }
    }
}
