//
//  AvatarInstaller.swift
//  PetAgent
//
//  F2 · owner: 강상우 (Sangwoo Kang)
//  Seeds the bundled dummy avatar into Application Support on first run.
//
//  AvatarLoader reads from ~/Library/Application Support/PetAgent/Avatars/
//  {name}/, but the only thing writing there was AvatarManagementView's
//  user-driven import — so a fresh clone launched with no avatar and the pet
//  never appeared. plan/02_pet-app.md requires the bundled dummy to make the
//  app run immediately after cloning.
//

import Foundation

enum AvatarInstaller {
    enum Outcome: Equatable {
        case installed
        /// Something is already installed under that name — left untouched.
        case alreadyPresent
        /// The app bundle carries no package to seed. usdz clips are Git LFS
        /// tracked and not committed yet, so this is a real state, not a bug.
        case noBundledPackage
        case failed(String)
    }

    /// Copies `bundledPackage` to `intoAvatarsDirectory/<package name>` unless
    /// something is already there. Never overwrites: the installed copy
    /// belongs to the user, who may have imported a real avatar over it.
    @discardableResult
    static func installIfNeeded(bundledPackage: URL, intoAvatarsDirectory avatarsDirectory: URL) -> Outcome {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: bundledPackage.path) else {
            return .noBundledPackage
        }

        let destination = avatarsDirectory.appendingPathComponent(bundledPackage.lastPathComponent, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            return .alreadyPresent
        }

        do {
            try fileManager.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: bundledPackage, to: destination)
            return .installed
        } catch {
            return .failed(String(describing: error))
        }
    }
}
