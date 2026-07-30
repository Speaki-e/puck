//
//  EditorWebView.swift
//  PetAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Embeds workspace's editor view bundle (file tree + Monaco) in the client
//  window, per plan/02_pet-app.md F13/plan/03_workspace.md 4.7. pet-app just
//  loads the URL workspace serves over its own local loopback server --
//  Monaco itself is never reimplemented natively (01_protocol.md 3.5).
//

import SwiftUI
import WebKit

struct EditorWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
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
                .foregroundStyle(ClientTheme.Colors.secondaryText)
            Text("이 워크스페이스에는 연결된 프로젝트가 없어요")
                .font(ClientTheme.Typography.sessionTitle)
                .foregroundStyle(ClientTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
