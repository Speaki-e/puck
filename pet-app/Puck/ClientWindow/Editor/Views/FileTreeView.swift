//
//  FileTreeView.swift
//  Puck
//
//  Recursive file tree with client-side substring search, mirroring
//  workspace's own FileTree.tsx behavior (full eager tree, not lazy/
//  virtualized -- WorkspaceFileService.listTree already walks the whole
//  project up front). Directories/files come pre-sorted from the service;
//  this view doesn't re-sort.
//
//  A real List(_:children:selection:) with .listStyle(.sidebar), not a
//  hand-rolled OutlineGroup+manual row backgrounds -- native macOS code
//  editors (CodeEdit, whose own CodeEditSourceEditor this app already
//  embeds; Xcode; Finder) all get their navigator's selection highlight,
//  hover state, and disclosure triangles from this exact system component
//  rather than reimplementing them, and so does this one now.
//

import SwiftUI

struct FileTreeView: View {
    let entries: [FileTreeEntry]
    let onOpen: (String) -> Void

    @State private var query = ""
    @State private var selection: String?
    @Environment(\.clientPalette) private var palette

    private var filtered: [FileTreeEntry] {
        guard !query.isEmpty else { return entries }
        return Self.filter(entries, query: query.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            List(filtered, children: \.children, selection: $selection) { entry in
                row(for: entry)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: selection) { _, newValue in
                guard let newValue, Self.entry(at: newValue, in: filtered)?.kind != .directory else { return }
                onOpen(newValue)
            }
        }
        .background(palette.surface)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            TextField(Strings.text(.editorSearchFiles), text: $query)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.caption)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(palette.background)
        .clipShape(Capsule())
        .padding(8)
    }

    private func row(for entry: FileTreeEntry) -> some View {
        Label {
            Text(entry.name)
                .font(ClientTheme.Typography.caption)
                .lineLimit(1)
                // lineLimit alone still lets a long name push the row wider
                // than the column and get clipped at the edge. Truncating at
                // the middle keeps both the start of the name and its
                // extension, which is what identifies a file.
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.name)
        } icon: {
            FileIconView(entry: entry)
        }
        .tag(entry.path)
    }

    private static func entry(at path: String, in entries: [FileTreeEntry]) -> FileTreeEntry? {
        for candidate in entries {
            if candidate.path == path { return candidate }
            if let children = candidate.children, let found = entry(at: path, in: children) { return found }
        }
        return nil
    }

    private static func filter(_ entries: [FileTreeEntry], query: String) -> [FileTreeEntry] {
        entries.compactMap { entry -> FileTreeEntry? in
            if entry.name.lowercased().contains(query) { return entry }
            guard let children = entry.children else { return nil }
            let filteredChildren = filter(children, query: query)
            guard !filteredChildren.isEmpty else { return nil }
            var copy = entry
            copy.children = filteredChildren
            return copy
        }
    }
}
