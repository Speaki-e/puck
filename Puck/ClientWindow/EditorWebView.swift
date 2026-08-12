//
//  EditorWebView.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Embeds workspace's editor view bundle (file tree + Monaco) in the client
//  window, per plan/02_pet-app.md F13/plan/03_workspace.md 4.7. pet-app just
//  loads the URL workspace serves over its own local loopback server --
//  Monaco itself is never reimplemented natively (01_protocol.md 3.5).
//

import SwiftUI
import WebKit

/// One live WKWebView per workspace, kept across editor-toggle and
/// workspace switches. Without this each toggle makes a fresh web view and
/// Monaco reloads from scratch -- scroll position, open tabs and any
/// unsaved edit in the editor go with it, which makes the toggle feel like
/// it closed the editor rather than hid it. The plan calls this a view
/// state toggle within one window (02_pet-app.md F13), so the editor has to
/// survive it.
///
/// ponytail: no eviction -- one web view per workspace the user actually
/// opened the editor for, freed only when PuckClient quits. Add an LRU cap
/// if someone works across enough projects for the memory to show.
@MainActor
final class EditorWebViewPool {
    static let shared = EditorWebViewPool()
    private var webViewsByWorkspace: [String: WKWebView] = [:]

    func webView(forWorkspace workspaceId: String) -> WKWebView {
        if let existing = webViewsByWorkspace[workspaceId] { return existing }
        let created = WKWebView()
        webViewsByWorkspace[workspaceId] = created
        return created
    }
}

struct EditorWebView: NSViewRepresentable {
    let workspaceId: String
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        EditorWebViewPool.shared.webView(forWorkspace: workspaceId)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

/// Shown instead of EditorWebView when the active workspace has no
/// project_path bound (protocol 3.5's editor_view_unavailable).
struct EditorUnavailableView: View {
    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingMedium) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("이 워크스페이스에는 연결된 프로젝트가 없어요")
                .font(ClientTheme.Typography.sessionTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
