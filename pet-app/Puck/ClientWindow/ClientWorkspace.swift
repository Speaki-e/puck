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
    /// nil for a pure-chat workspace -- code_editor and the editor pane are
    /// unavailable for it.
    var projectPath: String?
    /// Cached rather than recomputed on every read: resolving this touches
    /// the filesystem (EditorAvailability.resolve), and ClientWorkspace
    /// values get read from SwiftUI body evaluations often enough that a
    /// syscall there would be a real hot path. Refreshed via
    /// refreshEditorAvailability() -- see ClientWindowStore for the call
    /// sites (workspace creation, editor toggle opened, watcher-detected
    /// root loss).
    private(set) var editorAvailability: EditorAvailability

    init(id: String, name: String, projectPath: String?) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        editorAvailability = EditorAvailability.resolve(projectPath: projectPath)
    }

    var canOpenEditor: Bool {
        if case .ready = editorAvailability { return true }
        return false
    }

    mutating func refreshEditorAvailability() {
        editorAvailability = EditorAvailability.resolve(projectPath: projectPath)
    }
}
