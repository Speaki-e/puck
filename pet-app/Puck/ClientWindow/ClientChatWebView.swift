//
//  ClientChatWebView.swift
//  Puck
//
//  F13 chat rebuild · owner: 박해영 (Haeyoung Park)
//  Loads ../chat-web's static build (React/Tailwind/shadcn) into a WKWebView
//  via loadFileURL -- unlike EditorWebView.swift, this is never served over
//  a network. workspace must not own any chat/agent surface (docs/
//  decisions.md, 2026-08-13), so the chat UI is a bundle PuckClient owns
//  and drives directly through ClientChatBridge (a WKScriptMessageHandler),
//  not something workspace serves.
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

    /// `bridge` is registered as the "puckChat" message handler and attached
    /// to the created web view before the first load, so it can never miss
    /// the page's first `action:ready` message.
    func webView(bridge: ClientChatBridge) -> WKWebView {
        if let existing = webView { return existing }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(bridge, name: "puckChat")
        let created = WKWebView(frame: .zero, configuration: configuration)
        bridge.attach(webView: created)

        guard let indexURL = Bundle.main.url(forResource: "ChatWeb/index", withExtension: "html") else {
            assertionFailure("ChatWeb/index.html missing from bundle -- run scripts/sync-chat-web.sh before building")
            webView = created
            return created
        }
        // allowingReadAccessTo must be an ancestor of every file the page
        // references (assets/, fonts) -- the ChatWeb folder itself, not
        // just index.html, since relative ./assets/... URLs resolve
        // beneath it.
        created.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        webView = created
        return created
    }
}

struct ClientChatWebView: NSViewRepresentable {
    let bridge: ClientChatBridge

    func makeNSView(context: Context) -> WKWebView {
        ClientChatWebViewPool.shared.webView(bridge: bridge)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
