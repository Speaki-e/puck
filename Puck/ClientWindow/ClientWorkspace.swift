//
//  ClientWorkspace.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  A workspace (project folder or pure-chat) shown in the sidebar's
//  workspace switcher (plan/02_pet-app.md F13, plan/01_protocol.md 3.4).
//

import Foundation

struct ClientWorkspace: Identifiable, Equatable {
    let id: String
    var name: String
    /// nil for a pure-chat workspace -- code_editor and the editor view are
    /// unavailable for it (see editorUnavailableReason).
    var projectPath: String?
    /// Set once workspace confirms the embedded editor view bundle is being
    /// served (protocol 3.5); nil until then or if unavailable.
    var editorViewURL: URL?
    var editorUnavailableReason: EditorViewUnavailableReason?

    /// The editor toggle's enabled state. A URL only ever arrives via
    /// protocol 3.5's editor_view_ready, which workspace only sends for a
    /// workspace it actually bound a project_path to -- so this covers both
    /// "pure-chat workspace" and "workspace isn't connected yet" without
    /// pet-app second-guessing either.
    var canOpenEditor: Bool { editorViewURL != nil }
}
