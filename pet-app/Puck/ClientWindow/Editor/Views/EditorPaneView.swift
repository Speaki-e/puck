//
//  EditorPaneView.swift
//  Puck
//
//  Replaces EditorWebView -- a fully native file tree + tabs + syntax-
//  highlighted editor, backed directly by WorkspaceFileService instead of a
//  WKWebView pointed at workspace's EditorGateway. Branches on
//  ClientWorkspace's EditorAvailability, computed synchronously and locally
//  now that no round trip to workspace is needed to know whether a project
//  folder is usable.
//

import SwiftUI

struct EditorPaneView: View {
    let workspaceId: String
    let availability: EditorAvailability
    /// Called if store creation fails (the root turned out to be invalid at
    /// the moment of attaching) or a live store's watcher detects the root
    /// itself was moved/deleted -- the caller is expected to react by
    /// re-deriving ClientWorkspace.editorAvailability, this view doesn't own
    /// that decision.
    let onUnavailable: () -> Void

    @State private var store: EditorPaneStore?

    var body: some View {
        switch availability {
        case .noProject, .unavailable:
            EditorEmptyStateView(availability: availability)
        case .ready(let rootURL):
            if let store, store.workspaceId == workspaceId {
                EditorPaneContentView(store: store)
                    // Re-attach on a workspace switch. SwiftUI reuses this view
                    // when only its properties change, so onAppear does not
                    // fire again -- without this the pane kept showing the
                    // first project it was ever opened on while the sidebar,
                    // the status bar and the chat had all moved on.
                    .onChange(of: workspaceId) { attachStore(root: rootURL) }
            } else {
                Color.clear.onAppear { attachStore(root: rootURL) }
            }
        }
    }

    /// Idempotent for the workspace already attached; swaps the store
    /// otherwise. The pool keeps one store per workspace alive for the
    /// process's life, so switching back and forth costs nothing and keeps
    /// each workspace's open tabs.
    private func attachStore(root: URL) {
        guard store?.workspaceId != workspaceId else { return }
        do {
            store = try EditorPaneStorePool.shared.store(forWorkspace: workspaceId, root: root, onRootChanged: onUnavailable)
        } catch {
            onUnavailable()
        }
    }
}

private struct EditorPaneContentView: View {
    @ObservedObject var store: EditorPaneStore

    var body: some View {
        // A real resizable split, not a fixed-width HStack -- the navigator
        // pane in Xcode/CodeEdit/every other native macOS editor drags to
        // resize, and HSplitView is the system component for exactly that.
        HSplitView {
            FileTreeView(entries: store.tree, onOpen: { store.open(path: $0) })
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
            VStack(spacing: 0) {
                EditorTabStripView(
                    tabs: store.openTabs,
                    activeTabPath: store.activeTabPath,
                    canSave: store.canSaveActiveTab,
                    onSelect: { store.select(path: $0) },
                    onClose: { store.requestClose(path: $0) },
                    onSave: { store.saveActiveTab() }
                )
                Divider()
                EditorContentHostView(store: store)
            }
            .frame(minWidth: 360)
        }
        // Closing a tab with unsaved edits asks instead of dropping them.
        // A prompt rather than a silent save: the tab is a live view of a
        // file the agent also writes, and quietly committing a half-finished
        // draft on the way out is its own kind of damage. Three answers, in
        // the order macOS puts them.
        .confirmationDialog(
            "저장하지 않은 변경사항이 있어요",
            isPresented: Binding(
                get: { store.pendingClosePath != nil },
                set: { if !$0 { store.cancelPendingClose() } }
            ),
            titleVisibility: .visible
        ) {
            Button("저장 후 닫기") { store.confirmPendingCloseSaving() }
            Button("저장 안 함", role: .destructive) { store.confirmPendingCloseDiscarding() }
            Button("취소", role: .cancel) { store.cancelPendingClose() }
        } message: {
            Text(pendingCloseMessage)
        }
    }

    private var pendingCloseMessage: String {
        guard let path = store.pendingClosePath else { return "" }
        return "\((path as NSString).lastPathComponent)의 변경사항을 저장할까요?"
    }
}
