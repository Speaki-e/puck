import type { ActiveRun, RunRegistry } from "./run-registry.js";
import type { PendingApprovalStore } from "./pending-approval-store.js";

export interface RunCancellationDeps {
  runRegistry: Pick<RunRegistry, "listActive" | "cancel" | "abortAll" | "markDoneSent">;
  approvals: Pick<PendingApprovalStore, "rejectForRun" | "rejectAll">;
  sendAgentDone(input: { workspaceId: string; sessionId: string; ok: boolean; summary: string }): void;
}

/**
 * 세션 하나를 취소한다. 정리 순서는 W7 완료 기준 그대로: ActiveRun 중단(signal.abort) ->
 * (그 signal을 듣고 있는 petAppProxy/editorLocal이 알아서) pet 도구 취소 -> ACP session/cancel ->
 * 이 실행이 만든 대기 승인 거부 -> agent_done(ok=false, "중단됨") 전송.
 * agent_done은 markDoneSent로 정상 완료 경로와 경합해도 정확히 한 번만 나가도록 한다.
 */
export function cancelActiveRun(deps: RunCancellationDeps, sessionId: string): boolean {
  const run = deps.runRegistry.listActive().find((candidate) => candidate.sessionId === sessionId);
  if (!run) return false;
  deps.runRegistry.cancel(sessionId);
  deps.approvals.rejectForRun(run.runId);
  if (deps.runRegistry.markDoneSent(run.runId)) {
    deps.sendAgentDone({ workspaceId: run.workspaceId, sessionId: run.sessionId, ok: false, summary: "중단됨" });
  }
  return true;
}

/**
 * Agent Host 종료 시 진행 중이던 모든 ActiveRun을 실패 처리한다(W3/W7 완료 기준).
 * pet-app 연결 종료 시의 승인 자동 거부는 approvals.rejectAll()만 필요하므로 별도로 호출한다
 * (실행 자체는 Agent Host가 살아있는 한 계속 진행되고, 재연결 시 approval_response를 다시 받을
 * 대상이 없어졌을 뿐이다).
 */
export function failAllActiveRuns(deps: RunCancellationDeps, reason: string): ActiveRun[] {
  const runs = deps.runRegistry.listActive();
  deps.runRegistry.abortAll();
  for (const run of runs) {
    deps.approvals.rejectForRun(run.runId);
    if (deps.runRegistry.markDoneSent(run.runId)) {
      deps.sendAgentDone({ workspaceId: run.workspaceId, sessionId: run.sessionId, ok: false, summary: reason });
    }
  }
  return runs;
}
