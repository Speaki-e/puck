//
//  CodeTourDelegateTests.swift
//  Puck
//
//  show_code's body. Nothing here has an editor pane on screen, so the
//  point_at half is covered by its absence: the stop still succeeds, with a
//  reason, because the highlight is the part that always works.
//
//  EditorPaneStorePool.shared is a process-wide singleton with no eviction,
//  so every test uses its own freshly-generated workspaceId.
//

import XCTest
import CoreGraphics
@testable import Puck

final class CodeTourDelegateTests: XCTestCase {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("line1\nline2\nline3\n".utf8).write(to: root.appendingPathComponent("main.swift"))
        return root
    }

    func test_noProjectBound_failsWithAReason() async {
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in nil },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "a.swift", startLine: 1, endLine: 2, workspaceId: "w")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
        XCTAssertNotNil(result.detail)
    }

    /// A model that is a few lines off must not abort the tour.
    func test_lineNumbersPastTheEndAreClamped() {
        XCTAssertEqual(CodeTourDelegate.clamp(start: 1, end: 999, lineCount: 3), 1...3)
        XCTAssertEqual(CodeTourDelegate.clamp(start: 2, end: 2, lineCount: 3), 2...2)
        XCTAssertNil(CodeTourDelegate.clamp(start: 10, end: 12, lineCount: 3), "past the end entirely")
        XCTAssertEqual(CodeTourDelegate.clamp(start: 0, end: 2, lineCount: 3), 1...2, "1-indexed")
        XCTAssertEqual(CodeTourDelegate.clamp(start: 3, end: 1, lineCount: 3), 3...3, "end before start")
    }

    /// The stop opens the tab, shows the pane and publishes the range, even
    /// with no screen to point at.
    @MainActor
    func test_opensTheTabAndPublishesTheRange() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        var shownPanes: [String] = []
        let sut = CodeTourDelegate(
            resolveProjectPath: { $0 == workspaceId ? root.path : nil },
            showEditorPane: { workspace, _ in shownPanes.append(workspace) },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "main.swift", startLine: 2, endLine: 2, workspaceId: workspaceId)

        let store = try EditorPaneStorePool.shared.store(forWorkspace: workspaceId, root: root, onRootChanged: {})
        XCTAssertEqual(store.activeTabPath, "main.swift")
        XCTAssertEqual(store.pendingReveal?.lines, 2...2)
        XCTAssertEqual(shownPanes, [workspaceId])
        // No pane on screen in a test run, so the pet cannot be sent -- but
        // the code is highlighted, which is the half that matters.
        XCTAssertTrue(result.ok)
        XCTAssertNotNil(result.detail)
    }

    /// Naming a line the file does not have fails instead of pointing the pet
    /// at an arbitrary part of the file.
    @MainActor
    func test_startPastTheEndOfTheFileFails() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "main.swift", startLine: 99, endLine: 100, workspaceId: workspaceId)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
    }

    @MainActor
    func test_missingFileFails() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "gone.swift", startLine: 1, endLine: 1, workspaceId: UUID().uuidString)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
    }

    /// The model guesses paths -- it called show_code with a bare
    /// "AgentRunner.swift" on the first live run -- so a not-found failure
    /// says what a path is supposed to look like instead of only that this
    /// one was wrong.
    @MainActor
    func test_missingFileSaysHowPathsWork() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "gone.swift", startLine: 1, endLine: 1, workspaceId: UUID().uuidString)

        let detail = try XCTUnwrap(result.detail)
        XCTAssertTrue(detail.contains("상대 경로"), detail)
        XCTAssertTrue(detail.contains("list_files"), detail)
    }

    /// Only for failures a different path would fix. Telling the model to
    /// check list_files about a file that is simply too large sends it
    /// looking in the wrong place.
    func test_onlyPathFailuresGetThePathHint() {
        let tooLarge = WorkspaceFileServiceError(code: .fileTooLarge, message: "파일이 너무 커요")
        XCTAssertEqual(tooLarge.agentDetail, "파일이 너무 커요")
    }
}
