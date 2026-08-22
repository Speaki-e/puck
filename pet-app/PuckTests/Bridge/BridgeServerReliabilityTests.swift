//
//  BridgeServerReliabilityTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Covers code-review findings on commit 57615a8: listener failures were
//  silently swallowed (#1), and a stale-socket cleanup could steal a live
//  instance's socket (#3).
//

import XCTest
import Network
@testable import Puck

// MARK: - #1: listener failure detection

final class BridgeServerFailureMappingTests: XCTestCase {
    func test_failedState_mapsToError() {
        let error = NWError.posix(.EADDRINUSE)
        XCTAssertNotNil(BridgeServer.failureError(for: .failed(error)))
    }

    func test_waitingState_mapsToError() {
        let error = NWError.posix(.EACCES)
        XCTAssertNotNil(BridgeServer.failureError(for: .waiting(error)))
    }

    func test_readyState_mapsToNil() {
        XCTAssertNil(BridgeServer.failureError(for: .ready))
    }

    func test_cancelledState_mapsToNil() {
        XCTAssertNil(BridgeServer.failureError(for: .cancelled))
    }
}

// MARK: - #3: single-instance guard

final class BridgeServerInstanceGuardTests: XCTestCase {
    private var lockFileURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockFileURL = directory.appendingPathComponent("bridge.sock.lock")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: lockFileURL.deletingLastPathComponent())
    }

    func test_noLockFile_isNotRunning() {
        XCTAssertFalse(BridgeServer.isPetAppRunning(lockFileURL: lockFileURL))
    }

    func test_lockFileWithOwnLivePID_isRunning() throws {
        // The test process itself is a live PID we're allowed to signal.
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: lockFileURL)
        XCTAssertTrue(BridgeServer.isPetAppRunning(lockFileURL: lockFileURL))
    }

    func test_lockFileWithDeadPID_isNotRunning() throws {
        // PID 2^31-1 is not a valid/live process on any Mac.
        try Data("2147483647".utf8).write(to: lockFileURL)
        XCTAssertFalse(BridgeServer.isPetAppRunning(lockFileURL: lockFileURL))
    }

    func test_lockFileWithGarbageContents_isNotRunning() throws {
        try Data("not a pid".utf8).write(to: lockFileURL)
        XCTAssertFalse(BridgeServer.isPetAppRunning(lockFileURL: lockFileURL))
    }
}

// MARK: - #3: BridgeServer.start() end-to-end

final class BridgeServerStartGuardTests: XCTestCase {
    private var socketURL: URL!

    override func setUpWithError() throws {
        socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("bridge.sock")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
    }

    func test_start_throwsAlreadyRunning_whenLockFileNamesALiveProcess() throws {
        let lockFileURL = socketURL.appendingPathExtension("lock")
        try FileManager.default.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: lockFileURL)

        let server = BridgeServer(socketURL: socketURL)
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? BridgeServerError, .alreadyRunning)
        }
    }

    func test_startStopStart_succeeds_lockFileIsClearedOnStop() throws {
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        server.stop()

        // Should not see itself as "already running" after a clean stop.
        XCTAssertNoThrow(try server.start())
        server.stop()
    }

    /// stop() must clean up everything start() created. NWListener binds the
    /// socket path asynchronously, so this waits for the file to actually
    /// appear first — asserting removal without that wait passes vacuously
    /// (the file simply hasn't been created yet) while the real app leaks a
    /// stale socket into Application Support on every quit.
    func test_stop_removesBothLockFileAndSocketFile() throws {
        let server = BridgeServer(socketURL: socketURL)
        try server.start()

        let socketAppeared = expectation(description: "listener bound the socket path")
        pollUntil(timeout: 5, expectation: socketAppeared) {
            FileManager.default.fileExists(atPath: self.socketURL.path)
        }
        wait(for: [socketAppeared], timeout: 6)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: socketURL.appendingPathExtension("lock").path),
            "precondition: lock file should exist while running"
        )

        server.stop()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: socketURL.appendingPathExtension("lock").path),
            "lock file survived stop()"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: socketURL.path),
            "socket file survived stop()"
        )
    }

    private func pollUntil(timeout: TimeInterval, expectation: XCTestExpectation, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() {
                expectation.fulfill()
            } else if Date() < deadline {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
    }
}
