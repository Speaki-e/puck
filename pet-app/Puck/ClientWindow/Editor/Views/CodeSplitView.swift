//
//  CodeSplitView.swift
//  Puck
//
//  A file's contents, opened beside the conversation rather than in a pane
//  of its own.
//
//  Clicking a file in the explorer splits the agent's column instead of
//  replacing it: the reason to look at the file is usually what was just
//  said about it, and a layout that hides one to show the other makes you
//  choose. The tab strip and the unsaved-close prompt came with it from
//  EditorPaneView, which no longer has a code half.
//

import SwiftUI

struct CodeSplitView: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared

    @ObservedObject var store: EditorPaneStore
    /// A trailing closure at the call site, so the split reads as "code, and
    /// here is how to put it away".
    var onCollapse: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            EditorTabStripView(
                tabs: store.openTabs,
                activeTabPath: store.activeTabPath,
                canSave: store.canSaveActiveTab,
                onSelect: { store.select(path: $0) },
                onClose: { store.requestClose(path: $0) },
                onSave: { store.saveActiveTab() },
                onCollapse: onCollapse
            )
            Divider()
            EditorContentHostView(store: store)
        }
        // Closing a tab with unsaved edits asks instead of dropping them.
        // A prompt rather than a silent save: the tab is a live view of a
        // file the agent also writes, and quietly committing a half-finished
        // draft on the way out is its own kind of damage. Three answers, in
        // the order macOS puts them.
        .confirmationDialog(
            Strings.text(.editorUnsavedTitle),
            isPresented: Binding(
                get: { store.pendingClosePath != nil },
                set: { if !$0 { store.cancelPendingClose() } }
            ),
            titleVisibility: .visible
        ) {
            Button(Strings.text(.editorSaveAndClose)) { store.confirmPendingCloseSaving() }
            Button(Strings.text(.editorDiscard), role: .destructive) { store.confirmPendingCloseDiscarding() }
            Button(Strings.text(.commonCancel), role: .cancel) { store.cancelPendingClose() }
        } message: {
            Text(pendingCloseMessage)
        }
    }

    private var pendingCloseMessage: String {
        guard let path = store.pendingClosePath else { return "" }
        return String(format: Strings.text(.editorUnsavedMessageFormat), (path as NSString).lastPathComponent)
    }
}
