import { randomUUID } from "node:crypto";
import type { ApprovalPort } from "../shared/ports.js";
import type { RunRegistry } from "./run-registry.js";

export interface PendingApprovalStoreOptions {
  /** await_approval BridgeEvent 송신(01_protocol.md 3.6) -- PetBridge.sendEvent에 연결한다. */
  emit(input: { approvalId: string; summary: string; workspaceId: string; sessionId: string }): void;
  runRegistry?: Pick<RunRegistry, "attachApproval" | "detachApproval">;
}

interface PendingEntry {
  settle(approved: boolean): void;
  workspaceId: string;
  sessionId: string;
  runId: string;
}

/**
 * approval_id 발급·보관과 approval_response 매칭을 담당한다(plan/03_workspace.md 4.5, W7).
 * ai-module의 onApprovalRequired와 ACP requestPermission(acp-permission-bridge.ts) 둘 다
 * 이 하나의 저장소를 거쳐 같은 approval_id 발급 경로에 올라탄다.
 */
export class PendingApprovalStore implements ApprovalPort {
  private readonly pending = new Map<string, PendingEntry>();

  constructor(private readonly options: PendingApprovalStoreOptions) {}

  requestApproval(input: {
    runId: string;
    workspaceId: string;
    sessionId: string;
    source: "ai-module" | "acp";
    summary: string;
  }): Promise<boolean> {
    const approvalId = randomUUID();
    return new Promise<boolean>((resolve) => {
      this.pending.set(approvalId, {
        settle: resolve,
        workspaceId: input.workspaceId,
        sessionId: input.sessionId,
        runId: input.runId,
      });
      this.options.runRegistry?.attachApproval(input.runId, approvalId);
      this.options.emit({ approvalId, summary: input.summary, workspaceId: input.workspaceId, sessionId: input.sessionId });
    });
  }

  /**
   * pet-app -> workspace approval_response 처리. 모르는 id나 이미 처리된 id는 무시하고 false를
   * 반환한다(멱등, plan 4.5) -- 두 번째 resolve가 절대 일어나지 않는다.
   */
  respond(approvalId: string, approved: boolean): boolean {
    const entry = this.pending.get(approvalId);
    if (!entry) return false;
    this.settle(approvalId, entry, approved);
    return true;
  }

  /** 실행 취소 시 그 run이 만든 대기 승인을 전부 거부한다(W7). */
  rejectForRun(runId: string): void {
    for (const [approvalId, entry] of this.pending) {
      if (entry.runId === runId) this.settle(approvalId, entry, false);
    }
  }

  /** Agent Host 종료·pet-app 연결 종료 시 대기 중인 모든 승인을 거부한다(W7). */
  rejectAll(): void {
    for (const [approvalId, entry] of this.pending) this.settle(approvalId, entry, false);
  }

  get pendingCount(): number {
    return this.pending.size;
  }

  private settle(approvalId: string, entry: PendingEntry, approved: boolean): void {
    this.pending.delete(approvalId);
    this.options.runRegistry?.detachApproval(entry.runId, approvalId);
    entry.settle(approved);
  }
}
