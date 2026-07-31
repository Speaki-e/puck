//
//  AppDelegate.swift
//  ShaydiAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The Claude-Desktop-style client window used to live in-process inside
//  Shaydi; it moved here (2026-07-30) so it can be a regular, Dock-
//  resident app rather than sharing Shaydi's LSUIElement lifecycle
//  (byeolki: "별도의 앱으로 해서 dock에 상시 표시"). Shaydi still hosts
//  bridge.sock -- this app is just another client of it, identifying
//  itself with client_hello role "gui" (protocol 3.7).
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bridgeClient = BridgeSocketClient()
    private lazy var userInputSender = UserInputSender(transport: { [weak self] in self?.bridgeClient })
    private lazy var clientWindowStore = ClientWindowStore(sender: userInputSender)
    /// F15 (2026-07-31): the agent runs in this process now -- see AgentHost.
    private lazy var agentHost = AgentHost(broadcast: { [weak self] message in
        self?.bridgeClient.broadcast(message) ?? false
    })
    private var window: ClientWindow?
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // byeolki: "둘이 같이 가야하는거임" -- launching either app brings up
        // the other, since this app is useless without Shaydi hosting
        // bridge.sock on the other end.
        CompanionAppLauncher.launchIfNeeded(bundleIdentifier: AppIdentity.shaydiBundleID)

        setUpAppearance()

        bridgeClient.onMessage = { [weak self] message in
            DispatchQueue.main.async { self?.handle(message) }
        }
        bridgeClient.start()

        clientWindowStore.onUserCommand = { [weak self] text, workspaceId, sessionId in
            self?.agentHost.run(command: text, workspaceId: workspaceId, sessionId: sessionId)
        }
        clientWindowStore.onApprovalResolved = { [weak self] approvalId, approved in
            self?.agentHost.resolveApproval(id: approvalId, approved: approved)
        }
        clientWindowStore.onRunCancelled = { [weak self] in
            self?.agentHost.cancelPendingApprovals()
        }

        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// byeolki, 2026-08-01: "ShaydiAgent를 끄는 건 그냥 창을 닫아버리든
    /// 커맨드 큐를 하든 가능한데" -- closing the window quits the app, same
    /// as Cmd+Q, rather than lingering in the Dock with no window the way
    /// Mail/Notes do. This never touches Shaydi: CompanionAppLauncher only
    /// runs at each app's own launch, not on the other's quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Appearance (light/dark override)

    /// byeolki, 2026-08-01: "테마가 내가 아마 다크모드일텐데, 시스템모드랑
    /// 다크모드랑 생긴게 다른데?" -- ClientWindowStore.appearance used to
    /// have a doc comment claiming AppDelegate seeded/kept it live from
    /// SettingsStore, but nothing here ever actually did that: this process
    /// has no SettingsStore of its own (it would drag in HotkeyBindings and
    /// everything else that class depends on for one setting), so it reads
    /// Shaydi's UserDefaults domain directly and listens for the
    /// DistributedNotificationCenter broadcast Shaydi's own AppDelegate
    /// posts whenever the setting changes.
    private func setUpAppearance() {
        applyAppearance(currentAppearance())
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppAppearance.crossProcessChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance(self?.currentAppearance() ?? .system)
        }
    }

    private func currentAppearance() -> AppAppearance {
        let raw = UserDefaults(suiteName: AppIdentity.shaydiBundleID)?.string(forKey: AppAppearance.defaultsKey)
        return AppAppearance.resolved(fromDefaultsValue: raw)
    }

    private func applyAppearance(_ appearance: AppAppearance) {
        clientWindowStore.appearance = appearance
        NSApp.appearance = appearance.nsApplicationAppearance
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .event(let event, let workspaceId, let sessionId):
            clientWindowStore.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)
        case .workspaceCreate, .sessionCreate, .editorViewReady, .editorViewUnavailable:
            clientWindowStore.handleClientUpdate(message)
        case .toolResult(let result):
            // The reply to a tool this app's agent dispatched. pet-app sends
            // it back on the same connection, so it arrives here rather than
            // through the relay.
            agentHost.handle(result)
        case .userInput(let input):
            // Mirrored from pet-app's quick-capture bubble: typing there has
            // to bring this window up with the text already in the chat
            // (byeolki, 2026-07-30). Only shows the window if the message
            // actually landed in a session -- an unknown workspace/session
            // would pop an empty window for nothing.
            if clientWindowStore.showUserMessage(input.text, workspaceId: input.workspaceId, sessionId: input.sessionId) {
                showWindow()
                // F15: and it is a command, not just text to display -- the
                // pet's bubble and its push-to-talk are inputs to the same
                // agent the chat's own input bar feeds.
                agentHost.run(
                    command: input.text,
                    workspaceId: input.workspaceId ?? ClientWindowStore.defaultWorkspaceId,
                    sessionId: input.sessionId ?? ClientWindowStore.defaultSessionId
                )
            }
        default:
            break // relayed to this connection only ever as one of the above (protocol 3.7)
        }
    }

    private func showWindow() {
        let window = window ?? {
            // 720x480 was cramped for a sidebar + transcript + editor pane
            // (byeolki: "기본으로 보여지는 창의 크기를 좀 키워줘"), and at
            // origin (0,0) it opened in the bottom-left corner.
            let newWindow = ClientWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 740))
            let hosting = NSHostingController(rootView: ClientWindowView(store: clientWindowStore))
            // NSHostingController defaults to sizingOptions
            // .preferredContentSize, i.e. it keeps pushing the SwiftUI
            // fitting size onto the window -- which is why the window opened
            // at whatever the layout happened to fit in (~884x651, then
            // 700x471) no matter what contentRect or setContentSize said.
            hosting.sizingOptions = []
            newWindow.contentViewController = hosting
            newWindow.setContentSize(CGSize(width: 1100, height: 740))
            newWindow.minSize = CGSize(width: 760, height: 520)
            newWindow.center()
            self.window = newWindow
            return newWindow
        }()
        window.showAndActivate()
    }
}
