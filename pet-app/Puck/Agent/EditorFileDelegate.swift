//
//  EditorFileDelegate.swift
//  Puck
//
//  Lets the local agent (AgentRunner) reach read_file/open_in_editor, the
//  same way CodeEditorDelegate lets it reach code_editor. Placed here
//  (Puck/Agent, not PuckClient) for the same reason CodeEditorDelegate is:
//  PuckTests only depends on the Puck target, so anything that needs its
//  own test coverage has to live where @testable import Puck can reach it.
//
//  Unlike CodeEditorDelegate, this never crosses bridge.sock or waits on
//  workspace at all -- WorkspaceFileService/EditorPaneStorePool (also under
//  Puck/ClientWindow/Editor) read/write the project directly, so this type
//  is a thin adapter over them rather than a socket-correlation table.
//

import Foundation

final class EditorFileDelegate {
    /// workspaceId -> that workspace's bound project path, or nil for a
    /// pure-chat workspace / one AgentHost doesn't recognize. Injected
    /// rather than read from a store directly: this type has no business
    /// knowing ClientWindowStore exists, only that *something* can answer
    /// this one question.
    private let resolveProjectPath: (String) -> String?

    init(resolveProjectPath: @escaping (String) -> String?) {
        self.resolveProjectPath = resolveProjectPath
    }

    /// read_file's delegate body. A one-off WorkspaceFileService rather than
    /// going through EditorPaneStorePool -- a plain read has no tab/watcher
    /// state worth keeping alive, unlike openInEditor below.
    @MainActor
    func readFile(path: String, workspaceId: String) async -> DispatchedToolResult {
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: "이 워크스페이스에는 연결된 프로젝트가 없어요.")
        }
        do {
            let service = try WorkspaceFileService(root: URL(fileURLWithPath: projectPath, isDirectory: true))
            let content = try service.readFile(at: path)
            let data = JSONValue.object([
                "path": .string(content.path),
                "content": .string(content.content),
                "language": content.language.map(JSONValue.string) ?? .null,
                "size": .number(Double(content.size)),
                "readOnly": .bool(content.readOnly),
            ])
            return DispatchedToolResult(ok: true, data: data, error: nil, detail: nil)
        } catch let error as WorkspaceFileServiceError {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: error.message)
        } catch {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: error.localizedDescription)
        }
    }

    /// open_in_editor's delegate body. Goes through the same
    /// EditorPaneStorePool the visible editor pane uses, so the tab the
    /// agent opens is actually there when the user looks -- and if the user
    /// already has the pane open on this workspace, this reuses that exact
    /// store rather than creating a second, disconnected one.
    @MainActor
    func openInEditor(path: String, workspaceId: String) async -> DispatchedToolResult {
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: "이 워크스페이스에는 연결된 프로젝트가 없어요.")
        }
        do {
            let store = try EditorPaneStorePool.shared.store(
                forWorkspace: workspaceId,
                root: URL(fileURLWithPath: projectPath, isDirectory: true),
                onRootChanged: {}
            )
            store.open(path: path)
            if let lastError = store.lastError {
                return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: lastError.message)
            }
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        } catch let error as WorkspaceFileServiceError {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: error.message)
        } catch {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: error.localizedDescription)
        }
    }
}
