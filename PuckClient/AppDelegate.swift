//
//  AppDelegate.swift
//  PuckClient
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The Claude-Desktop-style client window used to live in-process inside
//  Puck; it moved here (2026-07-30) so it can be a regular, Dock-
//  resident app rather than sharing Puck's LSUIElement lifecycle
//  (byeolki: "별도의 앱으로 해서 dock에 상시 표시"). Puck still hosts
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
    private var settingsWindow: NSWindow?
    private var clientThemeStyleObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // byeolki: "둘이 같이 가야하는거임" -- launching either app brings up
        // the other, since this app is useless without Puck hosting
        // bridge.sock on the other end.
        CompanionAppLauncher.launchIfNeeded(bundleIdentifier: AppIdentity.puckBundleID)

        setUpClientThemeStyle()

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
        agentHost.onTaskSessionOpened = { [weak self] workspaceId, sourceSessionId, sessionId, title, userMessage in
            self?.clientWindowStore.moveTurnToTaskSession(
                workspaceId: workspaceId,
                from: sourceSessionId,
                to: sessionId,
                title: title,
                userMessage: userMessage
            )
        }

        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// byeolki, 2026-08-01: "PuckClient를 끄는 건 그냥 창을 닫아버리든
    /// 커맨드 큐를 하든 가능한데" -- closing the window quits the app, same
    /// as Cmd+Q, rather than lingering in the Dock with no window the way
    /// Mail/Notes do. This never touches Puck: CompanionAppLauncher only
    /// runs at each app's own launch, not on the other's quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Theme (ClientThemeStyle, synced from Puck's Settings)

    /// byeolki, 2026-08-02: "테마는 셰이디앱과 동기화 되어서 메뉴막대를 통한
    /// 셰이디 설정으로 변경할 수 있어야하거든" -- this process has no
    /// SettingsStore of its own (same reasoning as everywhere else this
    /// process reads Puck's UserDefaults domain directly instead), so it
    /// reads Puck's `clientThemeStyle` at launch and listens for the
    /// DistributedNotificationCenter broadcast Puck's AppDelegate posts
    /// whenever the setting changes -- the exact shape the old (2026-08-01,
    /// removed 2026-08-01, now reinstated here for a different value)
    /// AppAppearance cross-process wiring used.
    private func setUpClientThemeStyle() {
        applyClientThemeStyle(currentClientThemeStyle())
        clientThemeStyleObserver = DistributedNotificationCenter.default().addObserver(
            forName: ClientThemeStyle.crossProcessChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // The value travels with the notification itself -- re-reading
            // Puck's UserDefaults domain here would race against whether
            // that write had actually propagated by the time this
            // notification arrived (the same race AppAppearance's old
            // broadcast hit first); re-reading is only the fallback for a
            // notification that somehow arrived without one.
            let style = ClientThemeStyle.resolved(fromCrossProcessUserInfo: notification.userInfo)
                ?? self?.currentClientThemeStyle()
                ?? .dark
            self?.applyClientThemeStyle(style)
        }
    }

    private func currentClientThemeStyle() -> ClientThemeStyle {
        let raw = UserDefaults(suiteName: AppIdentity.puckBundleID)?.string(forKey: ClientThemeStyle.defaultsKey)
        return ClientThemeStyle.resolved(fromDefaultsValue: raw)
    }

    private func applyClientThemeStyle(_ style: ClientThemeStyle) {
        clientWindowStore.themeStyle = style
        // NSVisualEffectView materials (the `.glass` theme's sidebar) and
        // native chrome (NSOpenPanel, popovers) follow NSApp.appearance, not
        // SwiftUI's .preferredColorScheme, which never touches them -- same
        // reason Puck's own AppDelegate sets NSApp.appearance alongside
        // its SwiftUI modifier.
        NSApp.appearance = NSAppearance(named: style.colorScheme == .dark ? .darkAqua : .aqua)
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .event(let event, let workspaceId, let sessionId):
            clientWindowStore.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)
            // workspace's agent_done is also how a delegated code_editor call
            // finds out it finished (CodeEditorDelegate).
            agentHost.handle(event, sessionId: sessionId)
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

    // MARK: - Settings (F15 agent config, moved here 2026-08-02)

    /// Wired from ClientMainMenu's "설정…" (Cmd+,) item via the responder
    /// chain -- byeolki: "기존 셰이디앱에 있던 에이전트 관련 설정은 전부
    /// 셰이디에이전트 설정으로 옮기고". `@objc` and this exact selector name
    /// are load-bearing: ClientMainMenu references `Selector(("showSettings:"))`
    /// as a raw string rather than `#selector(AppDelegate.showSettings(_:))`
    /// so that file keeps compiling in PuckTests, which never links this
    /// class (see ClientMainMenu's own header comment).
    @objc private func showSettings(_ sender: Any?) {
        let window = settingsWindow ?? {
            let newWindow = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "설정"
            newWindow.isReleasedWhenClosed = false
            newWindow.applyGlassChrome()
            newWindow.contentViewController = NSHostingController(rootView: AgentSettingsView())
            newWindow.center()
            settingsWindow = newWindow
            return newWindow
        }()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            // Same numbers ClientWindowView declares as its own SwiftUI
            // minWidth/minHeight (ClientTheme.Metrics.windowMinWidth/
            // windowMinHeight) -- this is the constraint that's actually
            // enforced (sizingOptions = [] above means SwiftUI's own
            // .frame(minWidth:) never drives a real resize limit), so the two
            // had drifted apart before without anything catching it.
            newWindow.minSize = CGSize(width: ClientTheme.Metrics.windowMinWidth, height: ClientTheme.Metrics.windowMinHeight)
            newWindow.center()
            self.window = newWindow
            return newWindow
        }()
        window.showAndActivate()
    }
}
