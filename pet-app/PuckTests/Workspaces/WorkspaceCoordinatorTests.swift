//
//  WorkspaceCoordinatorTests.swift
//  PuckTests
//
//  The round trip that used to leave for workspace (Electron) and come back.
//  Covers what pet-bridge-router.ts's workspace_create_request /
//  session_create_request cases did, including the fallbacks.
//

import XCTest
@testable import Puck

final class WorkspaceCoordinatorTests: XCTestCase {
    private var root: URL!
    private var registry: WorkspaceRegistry!
    private var logged: [String] = []

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspaceCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = try WorkspaceRegistry(storageURL: root.appendingPathComponent("workspaces.json"))
        logged = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeCoordinator() -> WorkspaceCoordinator {
        WorkspaceCoordinator(workspaces: registry, log: { [weak self] line in self?.logged.append(line) })
    }

    private func makeProject() throws -> URL {
        let url = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - workspace_create_request

    func testCreateRequestIsAnsweredWithTheResolvedProjectPath() throws {
        let project = try makeProject()

        let replies = makeCoordinator()
            .handle(.workspaceCreateRequest(name: "puck", projectPath: project.path))

        guard case .workspaceCreate(let workspaceId, let name, let projectPath) = replies.first else {
            return XCTFail("expected a workspace_create, got \(replies)")
        }
        XCTAssertEqual(name, "puck")
        XCTAssertEqual(projectPath, project.resolvingSymlinksInPath().path)
        XCTAssertEqual(registry.get(id: workspaceId)?.name, "puck", "and it was persisted, not just echoed")
    }

    func testACreatedWorkspaceIsImmediatelyEditorReady() throws {
        let project = try makeProject()

        let replies = makeCoordinator()
            .handle(.workspaceCreateRequest(name: "puck", projectPath: project.path))

        guard case .workspaceCreate(_, _, let projectPath) = replies.first else {
            return XCTFail("expected a workspace_create, got \(replies)")
        }
        // The point of phase 1: the native editor pane can open without any
        // help from a second process.
        XCTAssertEqual(
            EditorAvailability.resolve(projectPath: projectPath),
            .ready(rootURL: URL(fileURLWithPath: project.resolvingSymlinksInPath().path, isDirectory: true))
        )
    }

    func testAnUnusableProjectPathIsRefusedRatherThanConfirmedWithoutOne() {
        let replies = makeCoordinator()
            .handle(.workspaceCreateRequest(name: "gone", projectPath: "/definitely/not/here"))

        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(logged.count, 1, "and it says so in the log rather than failing silently")
    }

    func testAChatOnlyWorkspaceIsStillCreated() {
        let replies = makeCoordinator().handle(.workspaceCreateRequest(name: "잡담", projectPath: nil))

        guard case .workspaceCreate(_, let name, let projectPath) = replies.first else {
            return XCTFail("expected a workspace_create, got \(replies)")
        }
        XCTAssertEqual(name, "잡담")
        XCTAssertNil(projectPath)
    }

    // MARK: - session_create_request

    func testSessionRequestIsAnsweredWithAUserOriginSession() {
        let replies = makeCoordinator()
            .handle(.sessionCreateRequest(workspaceId: "default", title: "새 채팅"))

        guard case .sessionCreate(let workspaceId, _, let title, let origin) = replies.first else {
            return XCTFail("expected a session_create, got \(replies)")
        }
        XCTAssertEqual(workspaceId, "default")
        XCTAssertEqual(title, "새 채팅")
        XCTAssertEqual(origin, .user)
    }

    func testASessionForAnUnknownWorkspaceFallsBackToDefault() {
        let replies = makeCoordinator()
            .handle(.sessionCreateRequest(workspaceId: "no-such-workspace", title: "x"))

        guard case .sessionCreate(let workspaceId, _, _, _) = replies.first else {
            return XCTFail("expected a session_create, got \(replies)")
        }
        XCTAssertEqual(workspaceId, WorkspaceRegistry.defaultWorkspaceID)
    }

    func testEachSessionRequestGetsItsOwnId() {
        let coordinator = makeCoordinator()

        let first = coordinator.handle(.sessionCreateRequest(workspaceId: "default", title: "a"))
        let second = coordinator.handle(.sessionCreateRequest(workspaceId: "default", title: "b"))

        guard case .sessionCreate(_, let firstId, _, _) = first.first,
              case .sessionCreate(_, let secondId, _, _) = second.first else {
            return XCTFail("expected two session_creates")
        }
        XCTAssertNotEqual(firstId, secondId)
    }

    // MARK: - Relay

    func testCreateRequestsNoLongerLeaveForWorkspace() {
        // Both are answered locally now; relaying them as well would mint a
        // competing workspace id for the same click.
        XCTAssertNil(ClientRelay.targetRole(for: .workspaceCreateRequest(name: "x", projectPath: nil)))
        XCTAssertNil(ClientRelay.targetRole(for: .sessionCreateRequest(workspaceId: "default", title: "x")))
    }

    func testConfirmationsStillGoToGUIConnections() {
        XCTAssertEqual(
            ClientRelay.targetRole(for: .workspaceCreate(workspaceId: "w", name: "n", projectPath: nil)),
            .gui
        )
        XCTAssertEqual(
            ClientRelay.targetRole(for: .sessionCreate(workspaceId: "w", sessionId: "s", title: "t", origin: .user)),
            .gui
        )
    }
}
