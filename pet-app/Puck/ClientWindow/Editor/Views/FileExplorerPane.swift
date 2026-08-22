//
//  FileExplorerPane.swift
//  Puck
//
//  The right-hand column: the project's files, and the CLI's past sessions,
//  behind a tab strip.
//
//  Split out of EditorPaneView, which used to hold the tree and the code side
//  by side. They are in different parts of the window now -- the tree on the
//  right, a file's contents beside the conversation -- so neither can own the
//  other, and both take the store from ClientWindowView.
//

import SwiftUI

/// What the right column is showing.
enum ExplorerTab: String, CaseIterable, Identifiable {
    case files
    case sessions

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .files: return "doc.on.doc"
        case .sessions: return "square.grid.2x2"
        }
    }

    var displayName: String {
        switch self {
        case .files: return Strings.text(.explorerTabFiles)
        case .sessions: return Strings.text(.explorerTabSessions)
        }
    }
}

struct FileExplorerPane: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: EditorPaneStore

    /// Kept for the window's life rather than per workspace: which of these
    /// someone wants open is about what they are doing, not which project.
    @State private var tab: ExplorerTab = .files
    /// Held here so it survives a tab switch: the sessions list is built from
    /// forty transcripts' worth of filesystem reads, and rescanning them for
    /// every glance at the file tree is work nobody asked for.
    @StateObject private var sessions = AgentSessionListModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabStrip
            Divider()
            switch tab {
            case .files:
                filesTab
            case .sessions:
                AgentSessionListView(model: sessions)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.background)
    }

    /// Icons rather than words. The column is 200pt and its job is the list
    /// under it; two labelled segments would take a third of the width to say
    /// what two icons say.
    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(ExplorerTab.allCases) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Image(systemName: candidate.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tab == candidate ? palette.textPrimary : palette.textSecondary)
                        .frame(width: 34, height: 28)
                        .contentShape(.rect)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(tab == candidate ? palette.accent : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.displayName)
                .help(candidate.displayName)
            }
            Spacer()
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
    }

    private var filesTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.text(.explorerHeader))
                .font(ClientTheme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
                .padding(.vertical, ClientTheme.Metrics.spacingMedium)
            FileTreeView(entries: store.tree, onOpen: { store.open(path: $0) })
        }
    }
}
