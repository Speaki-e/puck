//
//  AcpEventMapping.swift
//  Puck
//
//  Turns an ACP session/update into the BridgeEvent the rest of the app
//  already understands.
//
//  Nothing downstream changes because of this file, which is the point: the
//  transcript (ChatSession.apply), the pet's Type animation and its
//  detail.path jump (EventRouter) all keyed off events workspace used to emit
//  while relaying its own ACP stream. Emitting the same events from here keeps
//  every one of those behaviours without touching them.
//

import Foundation

enum AcpEventMapping {
    /// - Returns: the event to broadcast, or nil for updates that have no
    ///   equivalent (plans, thought chunks) -- dropped rather than forced into
    ///   a textChunk, which would put the agent's private reasoning in the
    ///   user's transcript.
    static func event(for update: AcpSessionUpdate, callID: String) -> BridgeEvent? {
        switch update.kind {
        case .agentMessageChunk:
            return update.text.isEmpty ? nil : .textChunk(text: update.text)

        case .toolCall, .toolCallUpdate:
            let call = update.raw["update"] ?? update.raw
            return .toolCall(
                id: call["toolCallId"]?.stringValue ?? callID,
                tool: "code_editor",
                args: nil,
                // EventRouter reads detail.path to make the pet jump when the
                // agent moves to a different file, so the path has to survive
                // the translation under exactly that key.
                detail: detail(from: call)
            )

        case .agentThoughtChunk:
            return .agentThinking

        case .plan, .none:
            return nil
        }
    }

    /// The file this update is about, if it names one. Same field the pet's
    /// detail.path jump reads -- pulled out separately so the editor can
    /// follow along without going through a BridgeEvent first.
    static func editedPath(in update: AcpSessionUpdate) -> String? {
        guard update.kind == .toolCall || update.kind == .toolCallUpdate else { return nil }
        let call = update.raw["update"] ?? update.raw
        return call["locations"]?.arrayValue?.first?["path"]?.stringValue
    }

    /// ACP reports touched files as `locations: [{path}]`; the pet's contract
    /// is a bare `{path}`. Falls back to the tool's title so a tool_call with
    /// no location still reads as something in the transcript.
    private static func detail(from call: JSONValue) -> JSONValue? {
        if let path = call["locations"]?.arrayValue?.first?["path"]?.stringValue {
            return .object(["path": .string(path)])
        }
        if let title = call["title"]?.stringValue {
            return .object(["title": .string(title)])
        }
        return nil
    }
}
