//
//  FileExplorerPane.swift
//  Puck
//
//  The project's files, as a column on the right edge of the window.
//
//  Split out of EditorPaneView, which used to hold the tree and the code
//  side by side. They are in different parts of the window now -- the tree on
//  the right, a file's contents beside the conversation -- so neither can own
//  the other, and both take the store from ClientWindowView.
//

import SwiftUI

struct FileExplorerPane: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: EditorPaneStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.text(.explorerHeader))
                .font(ClientTheme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
                .padding(.vertical, ClientTheme.Metrics.spacingMedium)
            FileTreeView(entries: store.tree, onOpen: { store.open(path: $0) })
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.background)
    }
}
