import { describe, expect, it, vi } from "vitest";
import { cancelActiveRun, failAllActiveRuns } from "./run-cancellation.js";
import { RunRegistry } from "./run-registry.js";
import { PendingApprovalStore } from "./pending-approval-store.js";

describe("cancelActiveRun", () => {
  it("존재하지 않는 세션은 false를 반환한다", () => {
    const runRegistry = new RunRegistry();
    const approvals = new PendingApprovalStore({ emit: vi.fn() });
    const sendAgentDone = vi.fn();
    expect(cancelActiveRun({ runRegistry, approvals, sendAgentDone }, "no-such-session")).toBe(false);
    expect(sendAgentDone).not.toHaveBeenCalled();
  });

  it("ActiveRun -> 승인 거부 -> agent_done(중단됨) 순서로 정리한다", async () => {
    const runRegistry = new RunRegistry();
    const approvals = new PendingApprovalStore({ emit: vi.fn(), runRegistry });
    const sendAgentDone = vi.fn();
    const { runId, signal } = runRegistry.begin("w1", "s1");
    const pendingApproval = approvals.requestApproval({ runId, workspaceId: "w1", sessionId: "s1", source: "ai-module", summary: "s" });

    expect(cancelActiveRun({ runRegistry, approvals, sendAgentDone }, "s1")).toBe(true);

    expect(signal.aborted).toBe(true);
    await expect(pendingApproval).resolves.toBe(false);
    expect(sendAgentDone).toHaveBeenCalledWith({ workspaceId: "w1", sessionId: "s1", ok: false, summary: "중단됨" });
    expect(sendAgentDone).toHaveBeenCalledTimes(1);
  });

  it("정상 완료 경로가 먼저 markDoneSent를 가져가면 취소 경로는 agent_done을 다시 보내지 않는다", () => {
    const runRegistry = new RunRegistry();
    const approvals = new PendingApprovalStore({ emit: vi.fn() });
    const sendAgentDone = vi.fn();
    const { runId } = runRegistry.begin("w1", "s1");
    expect(runRegistry.markDoneSent(runId)).toBe(true); // 정상 완료 콜백이 먼저 agent_done을 보낸 상황을 흉내
    cancelActiveRun({ runRegistry, approvals, sendAgentDone }, "s1");
    expect(sendAgentDone).not.toHaveBeenCalled();
  });
});

describe("failAllActiveRuns", () => {
  it("Agent Host 종료 시 모든 ActiveRun을 abort하고 각각 agent_done(reason)을 보낸다", () => {
    const runRegistry = new RunRegistry();
    const approvals = new PendingApprovalStore({ emit: vi.fn(), runRegistry });
    const sendAgentDone = vi.fn();
    const run1 = runRegistry.begin("w1", "s1");
    const run2 = runRegistry.begin("w1", "s2");
    approvals.requestApproval({ runId: run1.runId, workspaceId: "w1", sessionId: "s1", source: "ai-module", summary: "a" });

    const failed = failAllActiveRuns({ runRegistry, approvals, sendAgentDone }, "Agent Host 종료");

    expect(failed).toHaveLength(2);
    expect(run1.signal.aborted).toBe(true);
    expect(run2.signal.aborted).toBe(true);
    expect(sendAgentDone).toHaveBeenCalledTimes(2);
    expect(sendAgentDone).toHaveBeenCalledWith({ workspaceId: "w1", sessionId: "s1", ok: false, summary: "Agent Host 종료" });
    expect(approvals.pendingCount).toBe(0);
  });
});
