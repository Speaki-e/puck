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

    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: EditorPaneStore
    /// A trailing closure at the call site, so the split reads as "code, and
    /// here is how to put it away".
    var onCollapse: (() -> Void)?

    /// Whether the shell under the code is showing. Remembered across
    /// launches: someone who works with a terminal open wants it open the
    /// next morning too, and someone who never opens it never sees it.
    ///
    /// Only the button lives here; the terminal itself is drawn by
    /// ConversationSplit, one level up, so that it can be opened with no file
    /// open at all.
    @AppStorage("Puck.terminalOpen") private var isTerminalOpen = false

    var body: some View {
        VStack(spacing: 0) {
            EditorTabStripView(
                tabs: store.openTabs,
                activeTabPath: store.activeTabPath,
                canSave: store.canSaveActiveTab,
                onSelect: { store.select(path: $0) },
                onClose: { store.requestClose(path: $0) },
                onSave: { store.saveActiveTab() },
                onCollapse: onCollapse,
                isTerminalOpen: $isTerminalOpen
            )
            Divider()
            // Only when it says something the tab does not. A file at the
            // project root has a one-component path, and drawing it under a
            // tab with the same name on it is the same word twice.
            if let path = store.activeTabPath, path.contains("/") {
                breadcrumb(path)
                Divider()
            }
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

    /// The path of the file being edited, above it.
    ///
    /// The tab shows a file name, which is all that fits and not enough:
    /// three `index.ts` tabs are three identical labels, and in a project the
    /// interesting part of a path is the directories. Separators are drawn as
    /// chevrons so the components read as steps rather than as one long
    /// string.
    private func breadcrumb(_ path: String) -> some View {
        let components = path.split(separator: "/").map(String.init)
        return HStack(spacing: 3) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(palette.textSecondary.opacity(0.5))
                }
                Text(component)
                    .foregroundStyle(index == components.count - 1 ? palette.textPrimary : palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .font(ClientTheme.Typography.caption)
        .lineLimit(1)
        .truncationMode(.head)
        .padding(.horizontal, 10)
        .frame(height: 20)
        .help(path)
    }

    private var pendingCloseMessage: String {
        guard let path = store.pendingClosePath else { return "" }
        return String(format: Strings.text(.editorUnsavedMessageFormat), (path as NSString).lastPathComponent)
    }
}
