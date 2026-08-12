import { describe, expect, it } from "vitest";
import { DuplicateActiveRunError, RunRegistry } from "./run-registry.js";

describe("RunRegistry", () => {
  it("시작·완료 상태를 관리한다", () => {
    const registry = new RunRegistry();
    const { runId, signal } = registry.begin("w1", "s1");
    expect(signal.aborted).toBe(false);
    expect(registry.listActive()).toHaveLength(1);
    registry.finish(runId);
    expect(registry.listActive()).toHaveLength(0);
  });

  it("동일 세션의 중복 실행을 거부한다", () => {
    const registry = new RunRegistry();
    registry.begin("w1", "s1");
    expect(() => registry.begin("w1", "s1")).toThrow(DuplicateActiveRunError);
    // 다른 세션/워크스페이스는 막지 않는다
    expect(() => registry.begin("w1", "s2")).not.toThrow();
    expect(() => registry.begin("w2", "s1")).not.toThrow();
  });

  it("cancel은 session_id로 찾아 signal을 abort한다", () => {
    const registry = new RunRegistry();
    const { signal } = registry.begin("w1", "s1");
    expect(registry.cancel("s1")).toBe(true);
    expect(signal.aborted).toBe(true);
    expect(registry.cancel("unknown")).toBe(false);
  });

  it("finish 후에는 같은 세션을 다시 begin할 수 있다", () => {
    const registry = new RunRegistry();
    const { runId } = registry.begin("w1", "s1");
    registry.finish(runId);
    expect(() => registry.begin("w1", "s1")).not.toThrow();
  });

  it("승인 id를 실행에 연결하고 조회한다", () => {
    const registry = new RunRegistry();
    const { runId } = registry.begin("w1", "s1");
    registry.attachApproval(runId, "approval-1");
    registry.attachApproval(runId, "approval-2");
    expect(registry.approvalsFor(runId).sort()).toEqual(["approval-1", "approval-2"]);
    registry.detachApproval(runId, "approval-1");
    expect(registry.approvalsFor(runId)).toEqual(["approval-2"]);
  });

  it("markDoneSent는 같은 run에 대해 처음 한 번만 true를 반환한다", () => {
    const registry = new RunRegistry();
    const { runId } = registry.begin("w1", "s1");
    expect(registry.markDoneSent(runId)).toBe(true);
    expect(registry.markDoneSent(runId)).toBe(false);
    expect(registry.markDoneSent(runId)).toBe(false);
  });

  it("abortAll은 Agent Host 종료 시 모든 ActiveRun을 중단시킨다", () => {
    const registry = new RunRegistry();
    const run1 = registry.begin("w1", "s1");
    const run2 = registry.begin("w1", "s2");
    registry.abortAll();
    expect(run1.signal.aborted).toBe(true);
    expect(run2.signal.aborted).toBe(true);
  });
});
