//
//  ClientWindowStoreTests.swift
//  PetAgent
//
//  F13 test · owner: 박해영 (Haeyoung Park)
//  ClientWindowStore is the sidebar/session-list source of truth: workspace
//  switching, per-workspace session lists, and routing incoming chat events
//  to the right session (plan/02_pet-app.md F13, plan/01_protocol.md 3.4/3.5).
//

import XCTest
@testable import PetAgent

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

        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.timeline, [.done(ok: true, summary: "default workspace done")])
        XCTAssertEqual(store.session(workspaceId: "w2", sessionId: "default")?.timeline, [.done(ok: true, summary: "w2 done")])
    }

    func test_sessionCreate_userOrigin_appendsWithoutSwitchingActive() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s2", title: "new chat", origin: .user))

        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default", "s2"])
        XCTAssertEqual(store.activeSessionId, "default", "a user-requested new chat doesn't steal focus from what they were doing")
    }

    /// byeolki's design: the agent branching a casual chat into a task
    /// session should immediately bring the user along.
    func test_sessionCreate_agentOrigin_switchesActiveWorkspaceAndSession() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "fix the bug", origin: .agent))

        XCTAssertEqual(store.activeWorkspaceId, "w2")
        XCTAssertEqual(store.activeSessionId, "s9")
    }

    func test_editorViewReady_setsTheURLOnlyForItsOwnWorkspace() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: "/tmp/cat-house"))

        store.handleClientUpdate(.editorViewReady(workspaceId: "w2", url: "http://127.0.0.1:1/editor"))

        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.editorViewURL, URL(string: "http://127.0.0.1:1/editor"))
        XCTAssertNil(store.workspaces.first { $0.id == "default" }?.editorViewURL)
    }

    func test_editorViewUnavailable_setsTheReason() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.editorViewUnavailable(workspaceId: "default", reason: .noProjectPath))

        XCTAssertEqual(store.workspaces.first { $0.id == "default" }?.editorUnavailableReason, .noProjectPath)
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
}
