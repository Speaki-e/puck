//
//  RunShellHandlerTests.swift
//  Puck
//
//  F11 test · owner: Haeyoung Park
//  Argument validation + a real (harmless) command execution.
//

import XCTest
@testable import Puck

final class RunShellHandlerTests: XCTestCase {
    func test_missingCommand_failsWithExecutionFailed() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object([:])) { result in
            switch result {
            case .success:
                XCTFail("expected failure")
            case .failure(let error):
                XCTAssertEqual(error, .executionFailed("run_shell requires a command string"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_validCommand_returnsStdoutAndExitCode() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object(["command": .string("echo hello")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data else {
                    XCTFail("expected object result")
                    return
                }
                XCTAssertEqual(fields["stdout"], .string("hello\n"))
                XCTAssertEqual(fields["exit_code"], .number(0))
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    /// A child process writing more than the OS pipe buffer (64KB on macOS)
    /// blocks in write() until the parent drains the pipe. Waiting for exit
    /// before reading therefore deadlocks: the parent waits for a process that
    /// is waiting for the parent. Any real command the agent runs (a build, a
    /// test run, `git log`) clears 64KB easily.
    func test_outputLargerThanPipeBuffer_completesWithFullOutput() {
        let handler = RunShellHandler()
        let byteCount = 200_000

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object(["command": .string("printf 'x%.0s' {1..\(byteCount)}")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data else {
                    XCTFail("expected object result")
                    return
                }
                guard case .string(let stdout)? = fields["stdout"] else {
                    XCTFail("expected stdout string")
                    return
                }
                XCTAssertEqual(stdout.count, byteCount, "stdout was truncated at the pipe buffer boundary")
                XCTAssertEqual(fields["exit_code"], .number(0))
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }

    /// stderr fills its own pipe independently — draining only stdout still
    /// deadlocks a command that is noisy on stderr.
    func test_stderrLargerThanPipeBuffer_completesWithFullOutput() {
        let handler = RunShellHandler()
        let byteCount = 200_000

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object(["command": .string("printf 'e%.0s' {1..\(byteCount)} 1>&2")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data, case .string(let stderr)? = fields["stderr"] else {
                    XCTFail("expected stderr string")
                    return
                }
                XCTAssertEqual(stderr.count, byteCount, "stderr was truncated at the pipe buffer boundary")
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }

    /// A code review raised the concern that cancel() only terminates the
    /// direct zsh child, so a command that backgrounds a job (`sleep 30 &`)
    /// would survive as an orphan reparented to launchd. Verified false:
    /// Foundation's Process places its child in its own new process group,
    /// so terminate() (which signals that whole group, not just the one pid)
    /// already reaches jobs zsh backgrounded. This test is the regression
    /// guard for that verified behavior, not evidence of a bug that was fixed.
    func test_cancel_killsBackgroundedGrandchildProcesses() {
        let handler = RunShellHandler()
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck_test_bgpid_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        handler.execute(
            args: .object(["command": .string("sleep 30 & echo $! > \(pidFile.path); sleep 30")])
        ) { _ in
            // Not expected to complete in this test -- cancelled instead.
        }

        guard let backgroundPID = Self.waitForPID(at: pidFile, timeout: 2) else {
            XCTFail("background job never reported its pid")
            return
        }
        XCTAssertEqual(kill(backgroundPID, 0), 0, "background job should still be alive before cancel")

        handler.cancel()

        XCTAssertTrue(
            Self.waitUntilProcessDies(backgroundPID, timeout: 3),
            "cancel() must kill backgrounded child processes too, not just the direct zsh child"
        )
    }

    /// cancel() previously only sent SIGTERM (via Process.terminate()) with
    /// no escalation -- a command that traps/ignores SIGTERM survives
    /// indefinitely despite the caller already being told "cancelled" (found
    /// via review). This is the highest-privilege tool in the registry, so a
    /// cancel guarantee that a trap can defeat is worth closing.
    func test_cancel_escalatesToSIGKILL_whenTheProcessIgnoresSIGTERM() {
        let handler = RunShellHandler()
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck_test_trap_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        handler.execute(
            args: .object(["command": .string("echo $$ > \(pidFile.path); trap '' TERM; sleep 30")])
        ) { _ in
            // Not expected to complete in this test -- killed instead.
        }

        guard let pid = Self.waitForPID(at: pidFile, timeout: 2) else {
            XCTFail("trap-resistant process never reported its pid")
            return
        }
        XCTAssertEqual(kill(pid, 0), 0, "process should still be alive before cancel")

        handler.cancel()

        XCTAssertTrue(
            Self.waitUntilProcessDies(pid, timeout: 3),
            "cancel() must escalate to SIGKILL when the process ignores SIGTERM"
        )
    }

    private static func waitForPID(at file: URL, timeout: TimeInterval) -> pid_t? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: file, encoding: .utf8),
               let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            usleep(20_000)
        }
        return nil
    }

    private static func waitUntilProcessDies(_ pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            usleep(50_000)
        }
        return false
    }
}
