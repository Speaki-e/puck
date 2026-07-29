//
//  EventRouterTests.swift
//  PetAgent
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  Verifies the event -> reaction mapping table in
//  plan/02_pet-app.md section 3 F3 ("소켓 이벤트 -> 반응 매핑").
//

import XCTest
@testable import PetAgent

final class EventRouterTests: XCTestCase {
    func test_agentThinking_transitionsToIdle() {
        let reaction = EventRouter.reaction(for: .agentThinking)
        XCTAssertEqual(reaction, EventReaction(stateTransition: .idle, emotion: "thinking"))
    }

    func test_toolCall_codeEditor_transitionsToType() {
        let reaction = EventRouter.reaction(for: .toolCall(tool: "code_editor", detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type))
    }

    // MARK: - code_editor detail.path change -> jump (02_pet-app.md F3:
    // "detail.path 변경 시 짧은 점프") -- decoded via EventReaction.jump but
    // never actually checked for a change until now (found via spec
    // cross-check).

    func test_toolCall_codeEditor_firstEventEver_doesNotJump() {
        // Nothing to compare the very first path against -- entering Type
        // isn't itself a "change".
        let reaction = EventRouter.reaction(
            for: .toolCall(tool: "code_editor", detail: .object(["path": .string("src/main.ts")])),
            previousCodeEditorPath: nil
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: false))
    }

    func test_toolCall_codeEditor_samePathAsBefore_doesNotJump() {
        let reaction = EventRouter.reaction(
            for: .toolCall(tool: "code_editor", detail: .object(["path": .string("src/main.ts")])),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: false))
    }

    func test_toolCall_codeEditor_differentPathThanBefore_jumps() {
        let reaction = EventRouter.reaction(
            for: .toolCall(tool: "code_editor", detail: .object(["path": .string("src/other.ts")])),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: true))
    }

    func test_toolCall_runShell_neverJumpsRegardlessOfPreviousPath() {
        let reaction = EventRouter.reaction(
            for: .toolCall(tool: "run_shell", detail: nil),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point, jump: false))
    }

    func test_toolCall_runShell_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(tool: "run_shell", detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolCall_runAppleScript_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(tool: "run_applescript", detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolResult_failure_reactsWithTaskFailSFX() {
        let reaction = EventRouter.reaction(for: .toolResult(ok: false))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .reactClick, sfxKey: "task_fail", emotion: "sad"))
    }

    func test_toolResult_success_isNoOp() {
        let reaction = EventRouter.reaction(for: .toolResult(ok: true))
        XCTAssertEqual(reaction, EventReaction())
    }

    func test_awaitApproval_transitionsToPointWithWaitingSFX() {
        let reaction = EventRouter.reaction(for: .awaitApproval(summary: "rm -rf ./dist"))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point, sfxKey: "await_approval", emotion: "thinking"))
    }

    func test_agentDone_success_triggersSuccessSFXJumpAndBubble() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: true, summary: "3 tests passed"))
        XCTAssertEqual(
            reaction,
            EventReaction(sfxKey: "task_success", jump: true, bubbleText: "3 tests passed", emotion: "happy")
        )
    }

    func test_agentDone_failure_isNoOp() {
        // Not specified in the reaction table — only agent_done(ok=true) is; toolResult(ok=false)
        // already covers the failure-signaling case.
        let reaction = EventRouter.reaction(for: .agentDone(ok: false, summary: "failed"))
        XCTAssertEqual(reaction, EventReaction())
    }
}
