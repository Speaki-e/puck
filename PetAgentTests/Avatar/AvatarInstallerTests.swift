//
//  AvatarInstallerTests.swift
//  PetAgent
//
//  F2 test · owner: 강상우 (Sangwoo Kang)
//  AppDelegate loads the avatar from ~/Library/Application Support/PetAgent/
//  Avatars/dummy, but nothing ever put it there — only the user-driven import
//  in AvatarManagementView copies anything. On a fresh clone the app launched
//  with no avatar at all, which is exactly what plan/02_pet-app.md's "클론 즉시
//  실행 보장" rules out. The bundled package is seeded on first run instead.
//

import XCTest
@testable import PetAgent

final class AvatarInstallerTests: XCTestCase {
    private var bundled: URL!
    private var destinationRoot: URL!

    override func setUpWithError() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        bundled = sandbox.appendingPathComponent("Bundle/Avatars/dummy", isDirectory: true)
        destinationRoot = sandbox.appendingPathComponent("Support/Avatars", isDirectory: true)

        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: bundled.appendingPathComponent("manifest.json"))
        try FileManager.default.createDirectory(
            at: bundled.appendingPathComponent("sounds", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundled.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    func test_seedsTheBundledPackageWhenNothingIsInstalled() throws {
        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .installed)
        let installedManifest = destinationRoot.appendingPathComponent("dummy/manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedManifest.path))
    }

    func test_preservesSubdirectories() throws {
        _ = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        var isDirectory: ObjCBool = false
        let sounds = destinationRoot.appendingPathComponent("dummy/sounds")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sounds.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "the package layout must survive the copy")
    }

    /// The installed copy is the user's — they may have swapped in a real
    /// avatar via the import menu, or hand-edited the manifest. Re-seeding on
    /// every launch would silently throw that away.
    func test_doesNotOverwriteAnExistingInstall() throws {
        try FileManager.default.createDirectory(
            at: destinationRoot.appendingPathComponent("dummy", isDirectory: true),
            withIntermediateDirectories: true
        )
        let userManifest = destinationRoot.appendingPathComponent("dummy/manifest.json")
        try Data("{\"user\":true}".utf8).write(to: userManifest)

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .alreadyPresent)
        XCTAssertEqual(try Data(contentsOf: userManifest), Data("{\"user\":true}".utf8))
    }

    /// The bundle genuinely may not carry a package — usdz assets are Git LFS
    /// tracked and are not committed yet, so a build made without them must
    /// report that rather than appear to succeed.
    func test_reportsMissingBundledPackage() throws {
        let absent = bundled.deletingLastPathComponent().appendingPathComponent("nope", isDirectory: true)

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: absent, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .noBundledPackage)
    }
}
