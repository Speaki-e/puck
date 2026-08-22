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
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let entries: [FileTreeEntry]
    let onOpen: (String) -> Void
    /// Project-relative path to git's single letter for it -- M, A, D. Empty
    /// when the project is not a repository, or before the first read.
    ///
    /// On the tree rather than only in the git tab: which files a turn
    /// touched is the question the tree is being looked at with, and having
    /// to switch tabs to answer it means holding two lists in your head.
    var changedPaths: [String: String] = [:]
    /// What a right-click can do. Nil in a tree that only browses -- the
    /// detached window's, for one -- so the menu is absent rather than
    /// present and inert.
    var actions: FileTreeActions?

    @State private var query = ""
    @State private var selection: String?
    /// The row a name is being typed for, and what kind of thing the typing
    /// will produce. One prompt for renaming and both kinds of creation:
    /// all three ask for exactly one name.
    @State private var prompt: NamePrompt?
    /// The row whose Delete was picked, held until the confirmation is
    /// answered. Deleting is the one action here with no undo inside the app.
    @State private var pendingDeletion: FileTreeEntry?
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
        // On the whole tree, not only on a row: making a file at the top
        // level means right-clicking where there are no rows.
        .contextMenu {
            if let actions { creationItems(actions, parent: nil) }
        }
        .sheet(item: $prompt) { prompt in
            NamePromptSheet(prompt: prompt) { name in
                switch prompt.kind {
                case .rename: actions?.rename(prompt.path ?? "", name)
                case .newFile: actions?.create(name, false, prompt.path)
                case .newFolder: actions?.create(name, true, prompt.path)
                }
            }
        }
        .confirmationDialog(
            String(format: Strings.text(.explorerDeleteTitleFormat), pendingDeletion?.name ?? ""),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { entry in
            Button(Strings.text(.explorerDelete), role: .destructive) { actions?.trash(entry.path) }
            Button(Strings.text(.commonCancel), role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text(Strings.text(.explorerDeleteMessage))
        }
    }

    /// New file and new folder, made inside `parent` -- the directory that
    /// was right-clicked, or the project root when the click landed on empty
    /// space or on a file.
    @ViewBuilder
    private func creationItems(_ actions: FileTreeActions, parent: String?) -> some View {
        Button(Strings.text(.explorerNewFile)) {
            prompt = NamePrompt(kind: .newFile, path: parent, initialName: "")
        }
        Button(Strings.text(.explorerNewFolder)) {
            prompt = NamePrompt(kind: .newFolder, path: parent, initialName: "")
        }
    }

    /// The row menu: what can be done to this one thing, then what can be
    /// made next to it.
    @ViewBuilder
    private func rowMenu(for entry: FileTreeEntry, actions: FileTreeActions) -> some View {
        Button(Strings.text(.explorerRename)) {
            prompt = NamePrompt(kind: .rename, path: entry.path, initialName: entry.name)
        }
        Button(Strings.text(.explorerDelete), role: .destructive) { pendingDeletion = entry }
        Divider()
        creationItems(actions, parent: entry.kind == .directory ? entry.path : nil)
        Divider()
        Button(Strings.text(.explorerRevealInFinder)) { actions.revealInFinder(entry.path) }
        Button(Strings.text(.explorerCopyPath)) { actions.copyPath(entry.path) }
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
        .frame(height: 22)
        .background(palette.background)
        .clipShape(Capsule())
        // Tighter above than below, and tighter than it was on both: this
        // field is the only chrome left between the tab strip and the first
        // file, and it was sitting in a band of its own.
        .padding(.horizontal, 6)
        .padding(.top, 5)
        .padding(.bottom, 3)
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
        .badge(badge(for: entry))
        .tag(entry.path)
        .contextMenu {
            if let actions { rowMenu(for: entry, actions: actions) }
        }
    }

    /// Git's letter for a file, or -- for a directory -- how many files under
    /// it changed. A folder that says nothing while three files inside it did
    /// is a folder you have to open to learn anything.
    private func badge(for entry: FileTreeEntry) -> Text? {
        guard !changedPaths.isEmpty else { return nil }
        if entry.kind == .directory {
            let prefix = entry.path + "/"
            let count = changedPaths.keys.filter { $0.hasPrefix(prefix) }.count
            return count > 0 ? Text("\(count)") : nil
        }
        return changedPaths[entry.path].map { Text($0) }
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

/// What the explorer's menu can do, handed in rather than reached for: the
/// tree draws a project it does not own, and the store that does own it is
/// the one that has to hear about a rename.
struct FileTreeActions {
    let rename: (String, String) -> Void
    let trash: (String) -> Void
    /// (name, isDirectory, parent) -- parent nil means the project root.
    let create: (String, Bool, String?) -> Void
    let revealInFinder: (String) -> Void
    let copyPath: (String) -> Void
}

/// One name, being typed for one reason.
struct NamePrompt: Identifiable {
    enum Kind {
        case rename
        case newFile
        case newFolder
    }

    let kind: Kind
    /// The thing being renamed, or the directory being created in. Nil means
    /// the project root.
    let path: String?
    let initialName: String

    var id: String { "\(kind)#\(path ?? "")" }

    var title: String {
        switch kind {
        case .rename: return Strings.text(.explorerRenameTitle)
        case .newFile: return Strings.text(.explorerNewFileTitle)
        case .newFolder: return Strings.text(.explorerNewFolderTitle)
        }
    }

    var confirmTitle: String {
        kind == .rename ? Strings.text(.explorerRename) : Strings.text(.explorerCreate)
    }
}

/// A sheet rather than an inline field in the row.
///
/// Inline editing is what Finder does and it is nicer, but a `List` row that
/// swaps its label for a `TextField` loses first responder to the list's own
/// selection handling on macOS, and the workarounds are worse than a sheet
/// that is unambiguous about what is being named.
private struct NamePromptSheet: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

    let prompt: NamePrompt
    let onConfirm: (String) -> Void

    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingLarge) {
            Text(prompt.title)
                .font(ClientTheme.Typography.sectionHeader)
            TextField(Strings.text(.explorerNamePlaceholder), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(confirm)
                .frame(width: 260)
            HStack {
                Spacer()
                Button(Strings.text(.commonCancel), role: .cancel) { dismiss() }
                Button(prompt.confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(ClientTheme.Metrics.windowEdgePadding)
        .onAppear {
            name = prompt.initialName
            isFocused = true
        }
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}
