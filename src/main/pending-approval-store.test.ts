import { describe, expect, it, vi } from "vitest";
import { PendingApprovalStore } from "./pending-approval-store.js";
import { RunRegistry } from "./run-registry.js";

describe("PendingApprovalStore", () => {
  it("승인 요청 시 approval_id를 발급해 emit하고 응답으로 resolve된다", async () => {
    const emit = vi.fn();
    const store = new PendingApprovalStore({ emit });
    const pending = store.requestApproval({ runId: "r1", workspaceId: "w1", sessionId: "s1", source: "ai-module", summary: "빌드 폴더 삭제" });
    expect(emit).toHaveBeenCalledTimes(1);
    const approvalId = emit.mock.calls[0]![0].approvalId as string;
    expect(store.respond(approvalId, true)).toBe(true);
    await expect(pending).resolves.toBe(true);
  });

  it("같은 approval_id에 대한 두 번째 응답은 무시한다(멱등)", async () => {
    const emit = vi.fn();
    const store = new PendingApprovalStore({ emit });
    const pending = store.requestApproval({ runId: "r1", workspaceId: "w1", sessionId: "s1", source: "acp", summary: "s" });
    const approvalId = emit.mock.calls[0]![0].approvalId as string;
    expect(store.respond(approvalId, true)).toBe(true);
    expect(store.respond(approvalId, false)).toBe(false);
    await expect(pending).resolves.toBe(true);
  });

  it("알 수 없는 approval_id 응답은 무시한다", () => {
    const store = new PendingApprovalStore({ emit: vi.fn() });
    expect(store.respond("unknown-id", true)).toBe(false);
  });

  it("RunRegistry에 승인을 연결하고 응답 시 해제한다", async () => {
    const registry = new RunRegistry();
    const { runId } = registry.begin("w1", "s1");
    const store = new PendingApprovalStore({ emit: vi.fn(), runRegistry: registry });
    const pending = store.requestApproval({ runId, workspaceId: "w1", sessionId: "s1", source: "ai-module", summary: "s" });
    expect(registry.approvalsFor(runId)).toHaveLength(1);
    const approvalId = registry.approvalsFor(runId)[0]!;
    store.respond(approvalId, true);
    await pending;
    expect(registry.approvalsFor(runId)).toHaveLength(0);
  });

  it("rejectForRun은 해당 run의 대기 승인만 거부한다", async () => {
    const store = new PendingApprovalStore({ emit: vi.fn() });
    const pendingA = store.requestApproval({ runId: "runA", workspaceId: "w1", sessionId: "s1", source: "ai-module", summary: "a" });
    const pendingB = store.requestApproval({ runId: "runB", workspaceId: "w1", sessionId: "s2", source: "ai-module", summary: "b" });
    store.rejectForRun("runA");
    await expect(pendingA).resolves.toBe(false);
    expect(store.pendingCount).toBe(1);
    store.rejectForRun("runB");
    await expect(pendingB).resolves.toBe(false);
  });

  it("rejectAll은 대기 중인 모든 승인을 거부한다(Agent Host 종료/pet-app 연결 종료)", async () => {
    const store = new PendingApprovalStore({ emit: vi.fn() });
    const pendingA = store.requestApproval({ runId: "runA", workspaceId: "w1", sessionId: "s1", source: "ai-module", summary: "a" });
    const pendingB = store.requestApproval({ runId: "runB", workspaceId: "w1", sessionId: "s2", source: "acp", summary: "b" });
    store.rejectAll();
    await expect(pendingA).resolves.toBe(false);
    await expect(pendingB).resolves.toBe(false);
    expect(store.pendingCount).toBe(0);
  });
});
