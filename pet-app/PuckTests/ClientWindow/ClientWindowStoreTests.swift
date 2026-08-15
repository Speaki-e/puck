//
//  ClientWindowStoreTests.swift
//  Puck
//
//  F13 test · owner: 박해영 (Haeyoung Park)
//  ClientWindowStore is the sidebar/session-list source of truth: workspace
//  switching, per-workspace session lists, and routing incoming chat events
//  to the right session (plan/02_pet-app.md F13, plan/01_protocol.md 3.4/3.5).
//

import XCTest
@testable import Puck

private final class StubTransport: UserInputTransport {
    var hasConnectedClients = true
    private(set) var broadcasted: [BridgeMessage] = []

    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool {
        broadcasted.append(message)
        return true
    }
}

final class ClientWindowStoreTests: XCTestCase {
    /// `.done` carries a per-entry UUID now (two runs in one session used to
    /// collide on a fixed id), so its rows are matched on content.
    private func doneSummary(_ session: ChatSession?) -> String? {
        guard case .done(_, _, let summary)? = session?.timeline.last else { return nil }
        return summary
    }

    private func makeStore() -> (ClientWindowStore, StubTransport) {
        let transport = StubTransport()
        let store = ClientWindowStore(sender: UserInputSender { transport })
        return (store, transport)
    }

    func test_init_seedsTheDefaultWorkspaceAndItsCasualSession() {
        let (store, _) = makeStore()

        XCTAssertEqual(store.workspaces.map(\.id), ["default"])
        XCTAssertEqual(store.activeWorkspaceId, "default")
        XCTAssertEqual(store.activeSessionId, "default")
        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default"])
        XCTAssertEqual(store.sessions(in: "default").first?.origin, .user)
    }

    /// plan/02_pet-app.md F13: "워크스페이스마다 session_id: default인 일상
    /// 대화 세션이 항상 존재" -- a newly created workspace gets its own
    /// casual session automatically, without a separate session_create.
    func test_workspaceCreate_appendsTheWorkspaceAndSeedsItsOwnCasualSession() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: "/tmp/cat-house"))

        XCTAssertEqual(store.workspaces.map(\.id), ["default", "w2"])
        XCTAssertEqual(store.sessions(in: "w2").map(\.id), ["default"])
        // The default workspace's own casual session must be untouched.
        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default"])
    }

    /// Two different workspaces both having a session literally named
    /// "default" must not collide -- routing has to be keyed on the
    /// (workspace_id, session_id) pair, not session_id alone.
    func test_defaultSessionsInDifferentWorkspaces_areIndependent() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.handleChatEvent(.agentDone(ok: true, summary: "default workspace done"), workspaceId: "default", sessionId: "default")
        store.handleChatEvent(.agentDone(ok: true, summary: "w2 done"), workspaceId: "w2", sessionId: "default")

        XCTAssertEqual(doneSummary(store.session(workspaceId: "default", sessionId: "default")), "default workspace done")
        XCTAssertEqual(doneSummary(store.session(workspaceId: "w2", sessionId: "default")), "w2 done")
    }

    func test_sessionCreate_userOrigin_appendsWithoutSwitchingActive() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s2", title: "new chat", origin: .user))

        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default", "s2"])
        XCTAssertEqual(store.activeSessionId, "default", "a user-requested new chat doesn't steal focus from what they were doing")
    }

    /// The agent branching a casual chat into a task
    /// session should immediately bring the user along.
    func test_sessionCreate_agentOrigin_switchesActiveWorkspaceAndSession() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "fix the bug", origin: .agent))

        XCTAssertEqual(store.activeWorkspaceId, "w2")
        XCTAssertEqual(store.activeSessionId, "s9")
    }

    func test_workspaceCreate_withARealProjectPath_canOpenEditorImmediately() throws {
        let (store, _) = makeStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: root.path))

        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.editorAvailability, .ready(rootURL: URL(fileURLWithPath: root.path, isDirectory: true)))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, true)
    }

    func test_workspaceCreate_withAPathThatDoesNotExist_cannotOpenEditor() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "ghost house", projectPath: "/nonexistent/\(UUID().uuidString)"))

        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.editorAvailability, .unavailable(.pathMissing))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, false)
    }

    func test_refreshEditorAvailability_picksUpAProjectFolderDeletedAfterCreation() throws {
        let (store, _) = makeStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: root.path))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, true)

        try FileManager.default.removeItem(at: root)
        store.refreshEditorAvailability(forWorkspace: "w2")

        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.editorAvailability, .unavailable(.pathMissing))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, false)
    }

    /// A move,
    /// not a branch, so the chat the prompt was written in must not be left
    /// behind holding it.
    func test_moveTurnToTaskSession_closesTheChatItCameFromAndBringsTheMessage() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s-new", title: "새 채팅", origin: .user))

        store.moveTurnToTaskSession(
            workspaceId: "default",
            from: "s-new",
            to: "s-task",
            title: "hello.ts 주석 추가",
            userMessage: "hello.ts에 주석 달아줘"
        )

        let sessions = store.sessions(in: "default")
        XCTAssertEqual(sessions.map(\.id), ["default", "s-task"], "the source chat must be gone, not sitting empty")
        XCTAssertEqual(store.activeSessionId, "s-task")
        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "s-task")?.timeline.count, 1,
                       "the user's own message moves across -- otherwise the task session opens empty")
    }

    /// The casual session is the one exception: 02_pet-app.md F13 keeps
    /// `session_id: "default"` always present, and it holds conversation that
    /// has nothing to do with the task.
    func test_moveTurnToTaskSession_keepsTheCasualSession() {
        let (store, _) = makeStore()

        store.moveTurnToTaskSession(
            workspaceId: "default",
            from: "default",
            to: "s-task",
            title: "작업",
            userMessage: "고쳐줘"
        )

        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default", "s-task"])
        XCTAssertEqual(store.activeSessionId, "s-task")
    }

    /// The same session_create is announced on the socket and relayed straight
    /// back to this app, so it arrives after the local move already built the
    /// session. Re-creating it would wipe the message just moved in.
    func test_relayedSessionCreate_doesNotWipeTheSessionTheMoveAlreadyBuilt() {
        let (store, _) = makeStore()
        store.moveTurnToTaskSession(
            workspaceId: "default",
            from: "default",
            to: "s-task",
            title: "작업",
            userMessage: "고쳐줘"
        )

        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s-task", title: "작업", origin: .agent))

        XCTAssertEqual(store.sessions(in: "default").filter { $0.id == "s-task" }.count, 1)
        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "s-task")?.timeline.count, 1)
    }

    /// What the topBar's editor toggle is enabled by, and what
    /// ClientWindowView's workspace-switch fallback reads to decide whether
    /// to close the editor (F13 "화면 3분할", 2026-08-12).
    func test_canOpenEditor_falseForThePureChatDefaultWorkspace() {
        let (store, _) = makeStore()
        func workspace(_ id: String) -> ClientWorkspace? { store.workspaces.first { $0.id == id } }

        XCTAssertEqual(workspace("default")?.canOpenEditor, false)
    }

    func test_requestNewWorkspace_delegatesToSender() {
        let (store, transport) = makeStore()

        store.requestNewWorkspace(name: "cat house", projectPath: "/tmp/cat-house")

        XCTAssertEqual(transport.broadcasted, [.workspaceCreateRequest(name: "cat house", projectPath: "/tmp/cat-house")])
    }

    func test_requestNewSession_delegatesToSender() {
        let (store, transport) = makeStore()

        store.requestNewSession(title: "new chat", in: "default")

        XCTAssertEqual(transport.broadcasted, [.sessionCreateRequest(workspaceId: "default", title: "new chat")])
    }

    /// sendMessage routes through whichever workspace/session is currently active.
    func test_sendMessage_usesTheActiveWorkspaceAndSession() {
        let (store, transport) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))
        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "fix the bug", origin: .agent))

        store.sendMessage("go on", source: .text)

        XCTAssertEqual(transport.broadcasted, [.userInput(UserInput(text: "go on", source: .text, workspaceId: "w2", sessionId: "s9"))])
    }

    /// Text typed into pet-app's quick-capture bubble
    /// has to show up here. It arrives as a user_input with no workspace/
    /// session (the bubble knows nothing about either), which means the
    /// default workspace's casual session.
    func test_showUserMessage_withoutIds_landsInTheDefaultCasualSession() {
        let (store, _) = makeStore()

        XCTAssertTrue(store.showUserMessage("사파리 켜줘", workspaceId: nil, sessionId: nil))

        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.timeline.count, 1)
        XCTAssertEqual(store.activeWorkspaceId, "default")
        XCTAssertEqual(store.activeSessionId, "default")
    }

    func test_showUserMessage_switchesToTheSessionItWasSentTo() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        XCTAssertTrue(store.showUserMessage("hi", workspaceId: "w2", sessionId: "default"))

        XCTAssertEqual(store.activeWorkspaceId, "w2")
        XCTAssertEqual(store.activeSessionId, "default")
    }

    /// Same rule as handleChatEvent: an unknown session is dropped, not
    /// fabricated -- PuckClient keys "should I bring the window up?" off
    /// this, and an empty window popping open for a dropped message is worse
    /// than nothing.
    func test_showUserMessage_forAnUnknownSession_isDropped() {
        let (store, _) = makeStore()

        XCTAssertFalse(store.showUserMessage("hi", workspaceId: "nope", sessionId: "nope"))
    }

    // themeStyle moved to being a
    // Puck Settings item (see SettingsStoreTests' clientThemeStyle cases),
    // externally set here by PuckClient's AppDelegate rather than persisted
    // by this store, so there's nothing left to round-trip or fire a
    // callback on at this layer.
    func test_themeStyle_defaultsToDark_untilExternallySet() {
        let (store, _) = makeStore()

        XCTAssertEqual(store.themeStyle, .dark)
    }
}
