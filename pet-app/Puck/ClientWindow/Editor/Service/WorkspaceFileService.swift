//
//  WorkspaceFileService.swift
//  Puck
//
//  Swift port of workspace/src/main/file-service.ts -- the file I/O logic
//  the native editor pane needs, with no dependency on workspace (the
//  Electron app) being launched. Deliberately synchronous/throwing: these
//  are local-disk syscalls, not network calls, and callers (EditorPaneStore)
//  offload off the main thread when needed rather than this type adopting
//  async/await for its own sake.
//

import CryptoKit
import Foundation

enum WorkspaceFileServiceDefaults {
    static let editableSizeLimit = 2 * 1024 * 1024
    static let imagePreviewSizeLimit = 10 * 1024 * 1024
}

/// Skipped at every directory level, both in tree listing and (once wired,
/// see WorkspaceFileWatcher) file watching. Not `.gitignore`-aware, matching
/// file-service.ts's own deliberate choice -- see docs/file-tree-performance.md.
let workspaceFileServiceDefaultIgnores: Set<String> = [
    ".git", "node_modules", "dist", "dist-main", "release", ".next", "build",
    "target", ".venv", "venv", "__pycache__", ".pytest_cache", ".cache",
    "coverage", ".turbo", "Pods", ".build", "DerivedData",
]

final class WorkspaceFileService {
    let root: URL
    let editableSizeLimit: Int

    init(root: URL, editableSizeLimit: Int = WorkspaceFileServiceDefaults.editableSizeLimit) throws {
        self.root = try Self.realpath(root.standardizedFileURL)
        self.editableSizeLimit = editableSizeLimit
    }

    func listTree() throws -> [FileTreeEntry] {
        try readDirectory(root)
    }

    func readFile(at requestPath: String) throws -> FileContent {
        let target = try resolveExisting(requestPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: "파일 경로가 아닙니다")
        }
        let data = try Data(contentsOf: target)
        guard !Self.isBinary(data) else {
            throw WorkspaceFileServiceError(code: .binaryFile, message: "바이너리 파일은 편집할 수 없습니다")
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw WorkspaceFileServiceError(code: .encodingError, message: "UTF-8 텍스트 파일만 지원합니다")
        }
        let size = (attributes[.size] as? Int) ?? data.count
        return FileContent(
            path: relativeForWire(target),
            content: content,
            revision: Self.revision(of: data),
            readOnly: size > editableSizeLimit,
            size: size,
            language: EditorLanguage.displayName(forPath: target.path)
        )
    }

    func readImagePreview(at requestPath: String) throws -> FileContent {
        let target = try resolveExisting(requestPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: "파일 경로가 아닙니다")
        }
        let size = (attributes[.size] as? Int) ?? 0
        guard size <= WorkspaceFileServiceDefaults.imagePreviewSizeLimit else {
            throw WorkspaceFileServiceError(code: .fileTooLarge, message: "10MB를 초과하는 이미지는 미리 볼 수 없습니다")
        }
        let data = try Data(contentsOf: target)
        let extensionName = "." + target.pathExtension.lowercased()
        guard let detected = ImageMime.detect(data),
              let expected = ImageMime.extensionMap[extensionName],
              detected == expected else {
            throw WorkspaceFileServiceError(code: .binaryFile, message: "지원하는 이미지 형식과 실제 파일 내용이 일치하지 않습니다")
        }
        return FileContent(
            path: relativeForWire(target),
            content: "",
            revision: Self.revision(of: data),
            readOnly: true,
            size: size,
            language: "image",
            previewUrl: "data:\(detected);base64,\(data.base64EncodedString())",
            mimeType: detected
        )
    }

    func save(_ request: SaveFileRequest) throws -> SaveFileResult {
        let target = try resolveExisting(request.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: "파일 경로가 아닙니다")
        }
        let size = (attributes[.size] as? Int) ?? 0
        guard size <= editableSizeLimit else {
            throw WorkspaceFileServiceError(code: .fileTooLarge, message: "2MB를 초과하는 파일은 읽기 전용입니다")
        }
        let current = try Data(contentsOf: target)
        guard !Self.isBinary(current) else {
            throw WorkspaceFileServiceError(code: .binaryFile, message: "바이너리 파일은 저장할 수 없습니다")
        }
        guard Self.revision(of: current) == request.expectedRevision else {
            throw WorkspaceFileServiceError(code: .fileConflict, message: "디스크 파일이 마지막 읽기 이후 변경되었습니다")
        }
        guard let next = request.content.data(using: .utf8) else {
            throw WorkspaceFileServiceError(code: .encodingError, message: "UTF-8 텍스트 파일만 지원합니다")
        }
        guard next.count <= editableSizeLimit else {
            throw WorkspaceFileServiceError(code: .fileTooLarge, message: "저장할 내용이 2MB 제한을 초과합니다")
        }

        let temporary = target.deletingLastPathComponent().appendingPathComponent(
            ".\(target.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try next.write(to: temporary, options: .atomic)
            if let posixPermissions = attributes[.posixPermissions] {
                try? FileManager.default.setAttributes([.posixPermissions: posixPermissions], ofItemAtPath: temporary.path)
            }
            // replaceItemAt is the Foundation equivalent of file-service.ts's
            // temp-file-then-rename: atomic within the volume, preserves the
            // rest of the target's metadata. A concurrent writer (e.g. the
            // AI's code_editor tool, via a separate ACP subprocess) holding
            // the target open can make this throw -- normalized to
            // .fileConflict below, same intent as the TS EPERM/EBUSY branch,
            // though less selective about which underlying errors qualify.
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        } catch {
            throw WorkspaceFileServiceError(code: .fileConflict, message: "디스크 파일이 다른 프로세스에 의해 사용 중입니다")
        }
        return SaveFileResult(path: relativeForWire(target), revision: Self.revision(of: next), size: next.count)
    }

    // MARK: - Tree listing

    private struct DirEntry {
        let name: String
        let url: URL
        let isSymbolicLink: Bool
        let isDirectory: Bool
        let isRegularFile: Bool
    }

    private func readDirectory(_ directory: URL) throws -> [FileTreeEntry] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !workspaceFileServiceDefaultIgnores.contains($0) }
        let entries: [DirEntry] = names.compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]) else {
                return nil
            }
            let isSymlink = values.isSymbolicLink ?? false
            // Sort/dirent parity: a symlink is never treated as a directory
            // for ordering or branching purposes here, matching Node's
            // Dirent.isDirectory() (d_type-based, not target-resolved) that
            // file-service.ts sorts and branches on.
            return DirEntry(
                name: name,
                url: url,
                isSymbolicLink: isSymlink,
                isDirectory: !isSymlink && (values.isDirectory ?? false),
                isRegularFile: !isSymlink && (values.isRegularFile ?? false)
            )
        }
        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        var result: [FileTreeEntry] = []
        for entry in sorted {
            if entry.isSymbolicLink {
                guard let resolved = try? Self.realpath(entry.url), isInside(resolved.path) else { continue }
                result.append(FileTreeEntry(name: entry.name, path: relativeForWire(entry.url), kind: .symlink))
            } else if entry.isDirectory {
                result.append(FileTreeEntry(
                    name: entry.name,
                    path: relativeForWire(entry.url),
                    kind: .directory,
                    children: try readDirectory(entry.url)
                ))
            } else if entry.isRegularFile {
                result.append(FileTreeEntry(name: entry.name, path: relativeForWire(entry.url), kind: .file))
            }
        }
        return result
    }

    // MARK: - Path resolution

    private func resolveExisting(_ requestPath: String) throws -> URL {
        guard !requestPath.isEmpty, !requestPath.contains("\0") else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: "잘못된 파일 경로입니다")
        }
        let candidate = requestPath.hasPrefix("/")
            ? URL(fileURLWithPath: requestPath).standardizedFileURL
            : root.appendingPathComponent(requestPath).standardizedFileURL
        guard isInside(candidate.path) else {
            throw WorkspaceFileServiceError(code: .pathOutsideWorkspace, message: "프로젝트 밖 경로입니다")
        }
        let resolved = try Self.realpath(candidate)
        guard isInside(resolved.path) else {
            throw WorkspaceFileServiceError(code: .pathOutsideWorkspace, message: "심볼릭 링크가 프로젝트 밖을 가리킵니다")
        }
        return resolved
    }

    private func isInside(_ candidate: String) -> Bool {
        PathContainment.isInside(root: root.path, candidate: candidate)
    }

    private func relativeForWire(_ target: URL) -> String {
        PathContainment.relativePath(root: root.path, candidate: target.path) ?? target.path
    }

    // MARK: - Primitives

    /// realpath(3) directly, not URL.resolvingSymlinksInPath() -- the latter
    /// doesn't cleanly surface ENOENT for a nonexistent path, whereas this is
    /// the same primitive Node's fs.realpath (which file-service.ts uses)
    /// wraps. Also runs the result through .standardizedFileURL, which on
    /// Apple platforms silently collapses a leading "/private" (e.g.
    /// /private/var -> /var, since these ARE symlinks and Foundation
    /// special-cases them back out) -- realpath(3) expands that same
    /// symlink the other way, so without this the stored root and a freshly
    /// standardized candidate path would use different, incompatible string
    /// forms of the identical file and every containment check would fail.
    static func realpath(_ url: URL) throws -> URL {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard let resolvedC = Darwin.realpath(url.path, &buffer) else {
            if errno == ENOENT {
                throw WorkspaceFileServiceError(code: .fileNotFound, message: "파일을 찾을 수 없습니다")
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return URL(fileURLWithPath: String(cString: resolvedC)).standardizedFileURL
    }

    private static func isBinary(_ data: Data) -> Bool {
        data.prefix(min(data.count, 8192)).contains(0)
    }

    private static func revision(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
