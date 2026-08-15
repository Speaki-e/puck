//
//  AvatarCatalogue.swift
//  Puck
//
//  F2 · owner: 박해영 (Haeyoung Park)
//  Which avatar packages are actually installed -- needed so the avatar can
//  be switched like flipping between presets. AvatarInstaller
//  already lets differently-named packages coexist on disk; this just
//  enumerates them for a preset picker.
//

import Foundation

enum AvatarCatalogue {
    static var avatarsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(AppIdentity.applicationSupportDirectoryName)/Avatars", isDirectory: true)
    }

    /// Every folder under `avatarsDirectory` with a manifest.json, sorted by
    /// name. A folder missing one is a half-copied/broken install (the same
    /// standard AvatarInstaller itself uses), not a pickable preset.
    static func installedAvatarNames(in avatarsDirectory: URL = AvatarCatalogue.avatarsDirectory) -> [String] {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(at: avatarsDirectory, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { fileManager.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
            .map { $0.lastPathComponent }
            .sorted()
    }
}
