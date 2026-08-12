//
//  ClientChatWebView.swift
//  Puck
//
//  F13 chat rebuild · owner: 박해영 (Haeyoung Park)
//  Loads ../chat-web's static build (React/Tailwind/shadcn) into a WKWebView
//  via loadFileURL -- unlike EditorWebView.swift, this is never served over
//  a network. workspace must not own any chat/agent surface (docs/
//  decisions.md, 2026-08-13), so the chat UI is a bundle PuckClient owns
//  and drives directly through a WKScriptMessageHandler bridge
//  (ClientChatBridge.swift), not something workspace serves.
//
//  chat-web builds as a classic deferred script, not an ES module
//  (vite.config.ts): WKWebView silently refuses to execute
//  `<script type="module">` under file://, confirmed empirically. `defer`
//  (not a bare classic script) still matters -- main.tsx looks up #root,
//  which parses after <head>, so a script that runs immediately finds
//  nothing there (React error #299).
//

import SwiftUI
import WebKit

/// One persistent WKWebView for the whole app's lifetime -- unlike
/// EditorWebViewPool, chat isn't scoped per-workspace: the same webview
/// gets state pushed into it as the active workspace/session changes.
@MainActor
final class ClientChatWebViewPool {
    static let shared = ClientChatWebViewPool()
    private var webView: WKWebView?

    func webView(configuration: (WKWebView) -> Void) -> WKWebView {
        if let existing = webView { return existing }
        let created = WKWebView()
        webView = created
        configuration(created)
        return created
    }
}

struct ClientChatWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = ClientChatWebViewPool.shared.webView { webView in
            guard let indexURL = Bundle.main.url(forResource: "ChatWeb/index", withExtension: "html") else {
                assertionFailure("ChatWeb/index.html missing from bundle -- run scripts/sync-chat-web.sh before building")
                return
            }
            // allowingReadAccessTo must be an ancestor of every file the page
            // references (assets/, fonts) -- the ChatWeb folder itself, not
            // just index.html, since relative ./assets/... URLs resolve
            // beneath it.
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
