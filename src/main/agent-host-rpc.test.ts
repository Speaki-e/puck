import { describe, expect, it, vi } from "vitest";
import { AgentHostRpc } from "./agent-host-rpc.js";

describe("AgentHostRpc", () => {
  it("요청과 응답을 ID로 매칭한다", async () => {
    let sent: { id: string } | undefined;
    const rpc = new AgentHostRpc((message) => { sent = message as { id: string }; });
    const result = rpc.request("ping", { now: 1 });
    rpc.receive({ kind: "response", id: sent!.id, ok: true, payload: { now: 1, hostNow: 2 } });
    await expect(result).resolves.toEqual({ now: 1, hostNow: 2 });
  });

  it("Host 종료 시 모든 요청을 실패시킨다", async () => {
    const rpc = new AgentHostRpc(() => undefined);
    const result = rpc.request("ping", { now: 1 });
    rpc.failAll("host crashed");
    await expect(result).rejects.toThrow("host crashed");
    expect(rpc.pendingCount).toBe(0);
  });

  it("응답 제한 시간을 적용한다", async () => {
    vi.useFakeTimers();
    const rpc = new AgentHostRpc(() => undefined);
    const result = rpc.request("ping", { now: 1 }, 10);
    const assertion = expect(result).rejects.toThrow("시간 초과");
    await vi.advanceTimersByTimeAsync(11);
    await assertion;
    vi.useRealTimers();
  });
});
