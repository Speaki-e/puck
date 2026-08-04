import { randomUUID } from "node:crypto";
import type { RunRegistryPort } from "../shared/ports.js";

export interface ActiveRun {
  runId: string;
  workspaceId: string;
  sessionId: string;
  controller: AbortController;
  startedAt: number;
  /** 이 실행이 만든 승인 요청들 -- 취소 시 ActiveRun -> pet 도구 -> ACP -> 승인 순서로 정리하기 위한 연결점(W7). */
  approvalIds: Set<string>;
  /** agent_done을 정확히 한 번만 보내기 위한 가드 -- 정상 완료와 강제 취소 경로가 경합할 수 있다(W7). */
  doneSent: boolean;
}

export class DuplicateActiveRunError extends Error {
  constructor(readonly sessionId: string) {
    super(`세션에 이미 진행 중인 실행이 있습니다: ${sessionId}`);
    this.name = "DuplicateActiveRunError";
  }
}

/**
 * ActiveRun 시작·완료·취소·전체 실패 처리를 관리한다(plan/03_workspace.md W3).
 * 동일 세션 중복 실행 정책: SessionRouter가 이미 세션당 직렬 실행을 보장하지만, 방어적으로
 * 이 레지스트리도 같은 세션에 대한 중첩 begin()을 거부한다.
 */
export class RunRegistry implements RunRegistryPort {
  private readonly runs = new Map<string, ActiveRun>();
  private readonly bySession = new Map<string, string>();

  begin(workspaceId: string, sessionId: string): { runId: string; signal: AbortSignal } {
    const sessionKey = this.sessionKey(workspaceId, sessionId);
    if (this.bySession.has(sessionKey)) throw new DuplicateActiveRunError(sessionId);
    const runId = randomUUID();
    const controller = new AbortController();
    this.runs.set(runId, { runId, workspaceId, sessionId, controller, startedAt: Date.now(), approvalIds: new Set(), doneSent: false });
    this.bySession.set(sessionKey, runId);
    return { runId, signal: controller.signal };
  }

  finish(runId: string): void {
    const run = this.runs.get(runId);
    if (!run) return;
    this.runs.delete(runId);
    this.bySession.delete(this.sessionKey(run.workspaceId, run.sessionId));
  }

  /**
   * 현재 protocol(v0.5.0)의 run_cancel은 session_id만 싣는다(workspace_id/run_id 없음) --
   * 확장 계약은 protocol-extensions.ts의 ExtendedRunCancel로 준비돼 있지만 아직 wire로 나가지
   * 않는다. 그래서 이 메서드도 포트 정의(shared/ports.ts)와 마찬가지로 sessionId만 받는다.
   */
  cancel(sessionId: string): boolean {
    const run = this.findBySessionId(sessionId);
    if (!run) return false;
    run.controller.abort();
    return true;
  }

  attachApproval(runId: string, approvalId: string): void {
    this.runs.get(runId)?.approvalIds.add(approvalId);
  }

  detachApproval(runId: string, approvalId: string): void {
    this.runs.get(runId)?.approvalIds.delete(approvalId);
  }

  approvalsFor(runId: string): string[] {
    return [...(this.runs.get(runId)?.approvalIds ?? [])];
  }

  /**
   * agent_done을 이 실행에 대해 아직 보내지 않았다면 true를 반환하며 보낸 것으로 표시한다.
   * 정상 완료(onDone 콜백)와 강제 취소(cancelActiveRun)가 동시에 agent_done을 보내려 할 때
   * 먼저 도착한 쪽만 실제로 전송하도록 하는 가드(W7 완료 기준: "취소 완료 시 agent_done 전송"
   * 이 정상 종료와 중복되면 안 된다).
   */
  markDoneSent(runId: string): boolean {
    const run = this.runs.get(runId);
    if (!run || run.doneSent) return false;
    run.doneSent = true;
    return true;
  }

  get(runId: string): ActiveRun | undefined {
    return this.runs.get(runId);
  }

  listActive(): ActiveRun[] {
    return [...this.runs.values()];
  }

  /**
   * Agent Host 종료 시 대기 중인 모든 ActiveRun을 실패 처리하기 위한 진입점(W3 완료 기준).
   * 여기서는 신호만 abort한다 -- 실제 agent_done(ok=false) 송신과 finish() 호출은 각 실행을
   * 감싸는 호출자(run() 대기 코드)의 catch/finally가 맡는다.
   */
  abortAll(): void {
    for (const run of this.runs.values()) run.controller.abort();
  }

  private findBySessionId(sessionId: string): ActiveRun | undefined {
    return [...this.runs.values()].find((run) => run.sessionId === sessionId);
  }

  private sessionKey(workspaceId: string, sessionId: string): string {
    return `${workspaceId}::${sessionId}`;
  }
}
