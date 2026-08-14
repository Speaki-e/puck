//
//  EditorPaneStoreTests.swift
//  Puck
//
//  Runs against a real, temp-directory-backed WorkspaceFileService rather
//  than a hand-rolled fake -- WorkspaceFileServiceTests already covers that
//  type's own correctness in isolation, and local-disk I/O here is fast and
//  deterministic enough that a fake would only add an abstraction with no
//  real benefit over exercising the real integration.
//

import XCTest
@testable import Puck

final class EditorPaneStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ string: String, at relativePath: String) throws {
        let target = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: target)
    }

    private func makeStore() throws -> EditorPaneStore {
        try EditorPaneStore(workspaceId: "w1", root: root, onRootChanged: {})
    }

    func test_open_addsATabAndMakesItActive() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()

        store.open(path: "a.txt")

        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"])
        XCTAssertEqual(store.activeTabPath, "a.txt")
        XCTAssertEqual(store.activeTab?.content, "hello")
        XCTAssertFalse(store.activeTab?.isDirty ?? true)
    }

    func test_open_sameFileTwice_doesNotDuplicateTheTab() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()

        store.open(path: "a.txt")
        store.open(path: "a.txt")

        XCTAssertEqual(store.openTabs.count, 1)
    }

    func test_updateDraft_marksTheTabDirtyWithoutTouchingDisk() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")

        store.updateDraft(path: "a.txt", content: "hello world")

        XCTAssertTrue(store.activeTab?.isDirty ?? false)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "hello")
    }

    func test_save_writesToDiskAndClearsDirty() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "hello world")

        store.save(path: "a.txt")

        XCTAssertFalse(store.activeTab?.isDirty ?? true)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "hello world")
    }

    func test_close_removesTheTabAndFallsBackToTheLastRemaining() throws {
        try write("a", at: "a.txt")
        try write("b", at: "b.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.open(path: "b.txt")

        store.close(path: "b.txt")

        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"])
        XCTAssertEqual(store.activeTabPath, "a.txt")
    }

    func test_save_onExternalConflict_setsDiskChangedAndDoesNotOverwrite() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "my edit")

        // Simulate an external process changing the file after this tab read it.
        try write("changed elsewhere", at: "a.txt")

        store.save(path: "a.txt")

        XCTAssertEqual(store.lastError?.code, .fileConflict)
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "changed elsewhere", "a conflicting save must not touch the file on disk")
    }

    func test_useDisk_discardsTheDraftAndClearsConflict() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "my edit")
        try write("changed elsewhere", at: "a.txt")
        store.save(path: "a.txt")
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)

        store.useDisk(path: "a.txt")

        XCTAssertEqual(store.activeTab?.content, "changed elsewhere")
        XCTAssertFalse(store.activeTab?.isDirty ?? true)
        XCTAssertFalse(store.activeTab?.diskChanged ?? true)
    }

    func test_keepMine_reanchorsAndSavesTheDraft() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "my edit")
        try write("changed elsewhere", at: "a.txt")
        store.save(path: "a.txt")
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)

        store.keepMine(path: "a.txt")

        XCTAssertFalse(store.activeTab?.diskChanged ?? true)
        XCTAssertFalse(store.activeTab?.isDirty ?? true)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "my edit")
    }

    func test_readOnlyTab_ignoresDraftUpdatesAndSave() throws {
        try write(String(repeating: "x", count: 20), at: "big.txt")
        let store = try EditorPaneStore(workspaceId: "w1", root: root, editableSizeLimit: 10, onRootChanged: {})
        store.open(path: "big.txt")

        XCTAssertTrue(store.activeTab?.readOnly ?? false)

        store.updateDraft(path: "big.txt", content: "should be ignored")
        XCTAssertEqual(store.activeTab?.content, String(repeating: "x", count: 20))

        store.save(path: "big.txt")
        let onDisk = try String(contentsOf: root.appendingPathComponent("big.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, String(repeating: "x", count: 20), "a read-only tab's save must be a no-op")
    }
}
