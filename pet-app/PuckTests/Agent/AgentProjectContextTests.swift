//
//  AgentProjectContextTests.swift
//  PuckTests
//
//  Covers the three gaps behind "이 디렉토리 분석해줘" being unanswerable: the
//  agent was never told a project was open, had no tool that could list one,
//  and had a window tool whose name invited exactly that misuse.
//

import XCTest
@testable import Puck

final class WorkspaceContextTests: XCTestCase {
    func testAProjectBackedWorkspaceNamesItsFolder() {
        let context = AgentRunner.WorkspaceContext(name: "puck", projectPath: "/Users/x/puck")

        let line = context.promptLine

        XCTAssertTrue(line.contains("puck"))
        XCTAssertTrue(line.contains("/Users/x/puck"))
        // The phrases a user actually types. Without them the model has the
        // path but no reason to connect it to what was asked.
        XCTAssertTrue(line.contains("this directory"))
        XCTAssertTrue(line.contains("여기"))
    }

    func testAChatOnlyWorkspaceSaysThereAreNoFiles() {
        let context = AgentRunner.WorkspaceContext(name: "잡담", projectPath: nil)

        let line = context.promptLine

        XCTAssertTrue(line.contains("No project folder"))
        XCTAssertFalse(line.contains("relative"), "there is nothing for a path to be relative to")
    }
}

final class ListFilesToolTests: XCTestCase {
    private var project: URL!

    override func setUpWithError() throws {
        project = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListFilesToolTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("print(1)".utf8).write(to: project.appendingPathComponent("src/main.swift"))
        try Data("# hi".utf8).write(to: project.appendingPathComponent("README.md"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: project)
    }

    private func makeDelegate(projectPath: String?) -> EditorFileDelegate {
        EditorFileDelegate(resolveProjectPath: { _ in projectPath })
    }

    @MainActor
    func testItReturnsTheProjectsFilesAsRelativePaths() async {
        let result = await makeDelegate(projectPath: project.path).listFiles(workspaceId: "w1")

        XCTAssertTrue(result.ok)
        let files = result.data?["files"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertTrue(files.contains("README.md"))
        XCTAssertTrue(files.contains("src/main.swift"))
    }

    @MainActor
    func testDirectoriesAreFlattenedAwayLeavingOnlyFiles() async {
        let result = await makeDelegate(projectPath: project.path).listFiles(workspaceId: "w1")

        let files = result.data?["files"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertFalse(files.contains("src"), "a bare directory is not something the model can read")
    }

    @MainActor
    func testItReportsTheProjectPathSoTheModelCanNameIt() async {
        let result = await makeDelegate(projectPath: project.path).listFiles(workspaceId: "w1")

        XCTAssertEqual(
            result.data?["projectPath"]?.stringValue,
            URL(fileURLWithPath: project.path).resolvingSymlinksInPath().path
        )
    }

    @MainActor
    func testAChatOnlyWorkspaceExplainsItselfRatherThanReturningNothing() async {
        let result = await makeDelegate(projectPath: nil).listFiles(workspaceId: "w1")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.detail, "이 워크스페이스에는 연결된 프로젝트가 없어요.")
    }

    @MainActor
    func testALargeProjectIsTruncatedRatherThanFloodingTheContext() async throws {
        for index in 0..<(EditorFileDelegate.listFileLimit + 25) {
            try Data("x".utf8).write(to: project.appendingPathComponent("file-\(index).txt"))
        }

        let result = await makeDelegate(projectPath: project.path).listFiles(workspaceId: "w1")

        XCTAssertEqual(result.data?["files"]?.arrayValue?.count, EditorFileDelegate.listFileLimit)
        XCTAssertEqual(result.data?["truncated"]?.boolValue, true)
        // The real total is still reported, so the model can say the project
        // is bigger than what it was shown.
        let total = result.data?["totalCount"]?.numberValue ?? 0
        XCTAssertGreaterThan(total, Double(EditorFileDelegate.listFileLimit))
    }

    func testTheToolIsRegisteredWithoutRequiringApproval() {
        let tool = ToolRegistry.tool(named: "list_files")

        XCTAssertNotNil(tool)
        // Read-only: making the user approve it would tax the one call the
        // agent should reach for first.
        XCTAssertEqual(tool?.approval, .notRequired)
        XCTAssertTrue(tool?.parameters.isEmpty ?? false, "which project is not the model's choice")
    }
}
