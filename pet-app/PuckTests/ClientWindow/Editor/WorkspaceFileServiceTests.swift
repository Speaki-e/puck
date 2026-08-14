//
//  WorkspaceFileServiceTests.swift
//  Puck
//

import CryptoKit
import XCTest
@testable import Puck

final class WorkspaceFileServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService(editableSizeLimit: Int = WorkspaceFileServiceDefaults.editableSizeLimit) throws -> WorkspaceFileService {
        try WorkspaceFileService(root: root, editableSizeLimit: editableSizeLimit)
    }

    private func write(_ data: Data, at relativePath: String, in directory: URL? = nil) throws -> URL {
        let target = (directory ?? root).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target)
        return target
    }

    // MARK: - listTree

    func test_listTree_skipsDefaultIgnoredDirectories() throws {
        _ = try write(Data("x".utf8), at: "keep.txt")
        _ = try write(Data("x".utf8), at: "node_modules/pkg/index.js")
        _ = try write(Data("x".utf8), at: ".git/HEAD")

        let entries = try makeService().listTree()

        XCTAssertEqual(entries.map(\.name).sorted(), ["keep.txt"])
    }

    func test_listTree_sortsDirectoriesBeforeFilesThenAlphabetically() throws {
        _ = try write(Data("x".utf8), at: "b.txt")
        _ = try write(Data("x".utf8), at: "a.txt")
        _ = try write(Data("x".utf8), at: "zdir/inner.txt")

        let entries = try makeService().listTree()

        XCTAssertEqual(entries.map(\.name), ["zdir", "a.txt", "b.txt"])
        XCTAssertEqual(entries.first?.kind, .directory)
    }

    func test_listTree_includesSymlinkInsideRoot() throws {
        let target = try write(Data("x".utf8), at: "real.txt")
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let entries = try makeService().listTree()

        XCTAssertTrue(entries.contains { $0.name == "link.txt" && $0.kind == .symlink })
    }

    func test_listTree_excludesSymlinkEscapingRoot() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = root.appendingPathComponent("escape.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let entries = try makeService().listTree()

        XCTAssertFalse(entries.contains { $0.name == "escape.txt" })
    }

    // MARK: - readFile

    func test_readFile_returnsContentAndCorrectRevision() throws {
        let data = Data("hello world".utf8)
        _ = try write(data, at: "hello.txt")
        let expectedRevision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let content = try makeService().readFile(at: "hello.txt")

        XCTAssertEqual(content.content, "hello world")
        XCTAssertEqual(content.revision, expectedRevision)
        XCTAssertEqual(content.path, "hello.txt")
        XCTAssertFalse(content.readOnly)
    }

    func test_readFile_detectsLanguageFromExtension() throws {
        _ = try write(Data("x".utf8), at: "main.swift")

        let content = try makeService().readFile(at: "main.swift")

        XCTAssertEqual(content.language, "swift")
    }

    func test_readFile_rejectsBinaryContent() throws {
        _ = try write(Data([0x00, 0x01, 0x02, 0xff]), at: "binary.dat")

        XCTAssertThrowsError(try makeService().readFile(at: "binary.dat")) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .binaryFile)
        }
    }

    func test_readFile_rejectsNonUTF8Content() throws {
        // 0xff 0xfe alone (no BOM-following content) is not valid UTF-8, and
        // contains no null byte, so it reaches the UTF-8 decode check rather
        // than being caught as binary first.
        _ = try write(Data([0xff, 0xfe, 0xff, 0xfe]), at: "latin1.txt")

        XCTAssertThrowsError(try makeService().readFile(at: "latin1.txt")) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .encodingError)
        }
    }

    func test_readFile_isReadOnlyPastTheSizeLimit() throws {
        _ = try write(Data(repeating: 0x41, count: 20), at: "big.txt")

        let content = try makeService(editableSizeLimit: 10).readFile(at: "big.txt")

        XCTAssertTrue(content.readOnly)
    }

    func test_readFile_outsideRoot_throwsBeforeReading() throws {
        XCTAssertThrowsError(try makeService().readFile(at: "../../etc/passwd")) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .pathOutsideWorkspace)
        }
    }

    func test_readFile_missingFile_throwsFileNotFound() throws {
        XCTAssertThrowsError(try makeService().readFile(at: "missing.txt")) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .fileNotFound)
        }
    }

    // MARK: - readImagePreview

    private let pngSignature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

    func test_readImagePreview_returnsDataURLForValidPNG() throws {
        let data = Data(pngSignature + [0, 0, 0, 0])
        _ = try write(data, at: "image.png")

        let content = try makeService().readImagePreview(at: "image.png")

        XCTAssertEqual(content.mimeType, "image/png")
        XCTAssertTrue(content.previewUrl?.hasPrefix("data:image/png;base64,") ?? false)
        XCTAssertTrue(content.readOnly)
    }

    func test_readImagePreview_rejectsExtensionMismatchedWithMagicBytes() throws {
        // Real PNG bytes, but a .jpg extension -- expected/detected mismatch.
        let data = Data(pngSignature + [0, 0, 0, 0])
        _ = try write(data, at: "fake.jpg")

        XCTAssertThrowsError(try makeService().readImagePreview(at: "fake.jpg")) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .binaryFile)
        }
    }

    // The 10MB image-preview cap is fixed (not injectable like
    // editableSizeLimit), so exercising it in a unit test would need a real
    // 10MB fixture -- covered by manual verification instead (plan step 4).

    // MARK: - save

    func test_save_succeedsWithMatchingRevision() throws {
        let original = Data("first".utf8)
        _ = try write(original, at: "doc.txt")
        let service = try makeService()
        let read = try service.readFile(at: "doc.txt")

        let result = try service.save(SaveFileRequest(path: "doc.txt", content: "second", expectedRevision: read.revision))

        XCTAssertEqual(result.path, "doc.txt")
        let onDisk = try String(contentsOf: root.appendingPathComponent("doc.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "second")
    }

    func test_save_rejectsOnRevisionMismatch() throws {
        _ = try write(Data("first".utf8), at: "doc.txt")
        let service = try makeService()

        XCTAssertThrowsError(try service.save(SaveFileRequest(path: "doc.txt", content: "second", expectedRevision: "stale"))) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .fileConflict)
        }
        let onDisk = try String(contentsOf: root.appendingPathComponent("doc.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "first", "a rejected save must not touch the file on disk")
    }

    func test_save_rejectsOversizedContent() throws {
        let original = Data("first".utf8)
        _ = try write(original, at: "doc.txt")
        let service = try makeService(editableSizeLimit: 10)
        let read = try service.readFile(at: "doc.txt")

        XCTAssertThrowsError(try service.save(SaveFileRequest(
            path: "doc.txt",
            content: String(repeating: "x", count: 100),
            expectedRevision: read.revision
        ))) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .fileTooLarge)
        }
    }

    func test_save_outsideRoot_throwsBeforeAnyWrite() throws {
        let service = try makeService()

        XCTAssertThrowsError(try service.save(SaveFileRequest(
            path: "../../etc/passwd",
            content: "pwned",
            expectedRevision: "anything"
        ))) { error in
            XCTAssertEqual((error as? WorkspaceFileServiceError)?.code, .pathOutsideWorkspace)
        }
    }
}
