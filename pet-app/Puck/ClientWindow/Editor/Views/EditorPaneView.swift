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
            if let store {
                EditorPaneContentView(store: store)
            } else {
                Color.clear.onAppear { attachStore(root: rootURL) }
            }
        }
    }

    private func attachStore(root: URL) {
        guard store == nil else { return }
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
                    onSelect: { store.select(path: $0) },
                    onClose: { store.close(path: $0) }
                )
                Divider()
                EditorContentHostView(store: store)
            }
            .frame(minWidth: 360)
        }
    }
}
