//
//  PathContainment.swift
//  Puck
//
//  Swift port of workspace/src/shared/path-containment.ts.
//

import Foundation

enum PathContainment {
    /// Whether `candidate` equals `root` or sits inside it. Both must
    /// already be absolute, standardized paths -- this does no resolution
    /// itself (see WorkspaceFileService.realpath for the symlink-aware step).
    static func isInside(root: String, candidate: String) -> Bool {
        let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
    }
}
