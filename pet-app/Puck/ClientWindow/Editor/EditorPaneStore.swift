//
//  EditorPaneStore.swift
//  Puck
//
//  Source of truth for one workspace's editor pane: file tree, open tabs,
//  which one is active. Owns the WorkspaceFileService (root validated at
//  construction, so a failed init means the project folder is genuinely
//  gone/inaccessible right now) and the WorkspaceFileWatcher that keeps the
//  tree and open tabs' diskChanged state live.
//

import Foundation

final class EditorPaneStore: ObservableObject {
    let workspaceId: String

    @Published private(set) var tree: [FileTreeEntry] = []
    @Published private(set) var openTabs: [EditorTab] = []
    @Published var activeTabPath: String?
    @Published var lastError: WorkspaceFileServiceError?

    private let service: WorkspaceFileService
    private var watcher: WorkspaceFileWatcher?

    /// Called (on the main queue) if the project root itself is moved/
    /// deleted while this store is alive -- the owner is expected to react
    /// by re-deriving ClientWorkspace.editorAvailability rather than this
    /// type owning that decision itself. A `var`, not baked into the
    /// watcher at construction: EditorPaneStorePool.store(forWorkspace:...)
    /// can return an existing store created by an earlier caller (e.g. a
    /// tool call, which has no ClientWorkspace to refresh and passes a
    /// no-op), and a later caller that *does* care about root-loss (the
    /// real editor pane UI) needs its callback to actually take over rather
    /// than silently losing detection to whichever caller happened to
    /// create the store first.
    var onRootChanged: (() -> Void)?

    init(
        workspaceId: String,
        root: URL,
        editableSizeLimit: Int = WorkspaceFileServiceDefaults.editableSizeLimit,
        onRootChanged: @escaping () -> Void
    ) throws {
        self.workspaceId = workspaceId
        self.onRootChanged = onRootChanged
        service = try WorkspaceFileService(root: root, editableSizeLimit: editableSizeLimit)
        loadTree()
        let watcher = WorkspaceFileWatcher(
            root: service.root,
            onChange: { [weak self] changes in self?.handleFileSystemChanges(changes) },
            onRootChanged: { [weak self] in self?.onRootChanged?() }
        )
        self.watcher = watcher
        watcher.start()
    }

    deinit {
        watcher?.stop()
    }

    var activeTab: EditorTab? {
        guard let activeTabPath else { return nil }
        return openTabs.first { $0.path == activeTabPath }
    }

    func loadTree() {
        do {
            tree = try service.listTree()
        } catch {
            lastError = error as? WorkspaceFileServiceError
        }
    }

    func open(path: String) {
        if openTabs.contains(where: { $0.path == path }) {
            activeTabPath = path
            return
        }
        do {
            let content = Self.isImagePath(path) ? try service.readImagePreview(at: path) : try service.readFile(at: path)
            openTabs.append(EditorTab(content))
            activeTabPath = path
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    func select(path: String) {
        guard openTabs.contains(where: { $0.path == path }) else { return }
        activeTabPath = path
    }

    func close(path: String) {
        openTabs.removeAll { $0.path == path }
        if activeTabPath == path {
            activeTabPath = openTabs.last?.path
        }
    }

    func updateDraft(path: String, content: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }), !openTabs[index].readOnly else { return }
        openTabs[index].content = content
    }

    func save(path: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }), !openTabs[index].readOnly else { return }
        let tab = openTabs[index]
        do {
            let result = try service.save(SaveFileRequest(path: path, content: tab.content, expectedRevision: tab.revision))
            openTabs[index].savedContent = tab.content
            openTabs[index].revision = result.revision
            openTabs[index].diskChanged = false
        } catch let error as WorkspaceFileServiceError {
            if error.code == .fileConflict {
                openTabs[index].diskChanged = true
            }
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Conflict resolution: keep the in-editor draft, re-anchored to disk's
    /// current revision, then retry the save. No diff view -- this and
    /// useDisk are the only two resolutions offered.
    func keepMine(path: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }) else { return }
        do {
            let fresh = try service.readFile(at: path)
            openTabs[index].revision = fresh.revision
            save(path: path)
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Conflict resolution: discard the draft, load whatever's on disk now.
    func useDisk(path: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }) else { return }
        do {
            let fresh = try service.readFile(at: path)
            openTabs[index] = EditorTab(fresh)
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Internal rather than private so the adopt-vs-warn decision can be
    /// driven directly: FSEvents delivery is WorkspaceFileWatcherTests'
    /// subject, and going through a real OS event to reach this branch makes
    /// a logic test depend on scheduling it has no stake in.
    func handleFileSystemChanges(_ changes: [FileSystemChange]) {
        loadTree()
        for change in changes {
            guard let relativePath = relativePath(for: change.path),
                  let index = openTabs.firstIndex(where: { $0.path == relativePath }) else { continue }
            if change.kind == .unlink {
                openTabs[index].diskChanged = true
                continue
            }
            guard change.kind == .change else { continue }
            // Re-read and compare revisions rather than trusting the raw FS
            // event alone -- our own just-completed save fires this same
            // event, and would otherwise flag itself as an external conflict.
            guard let fresh = try? service.readFile(at: relativePath), fresh.revision != openTabs[index].revision else { continue }
            // A tab the user has not touched follows the file (2026-08-15).
            // The conflict banner is the right answer for an edit the user
            // would lose and the wrong one for a file they are only watching
            // -- which is the whole of the code_editor case, where every
            // change is one the agent was asked to make. Dirty tabs still
            // get the banner: nothing silently overwrites typing.
            if openTabs[index].isDirty {
                openTabs[index].diskChanged = true
            } else {
                openTabs[index].adopt(fresh)
            }
        }
    }

    private func relativePath(for absolutePath: String) -> String? {
        let rootPath = service.root.path
        guard absolutePath.hasPrefix(rootPath) else { return nil }
        var relative = String(absolutePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    private static func isImagePath(_ path: String) -> Bool {
        ImageMime.extensionMap["." + (path as NSString).pathExtension.lowercased()] != nil
    }
}
