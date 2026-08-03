import { describe, expect, it } from "vitest";
import { SessionRegistry } from "./session-registry.js";

describe("SessionRegistry", () => {
  it("session_create_request용으로 새 id를 발급하고 기록한다", () => {
    const registry = new SessionRegistry();
    const record = registry.record("w1", "버그 수정", "user");
    expect(record.workspaceId).toBe("w1");
    expect(record.origin).toBe("user");
    expect(registry.get(record.id)).toEqual(record);
  });

  it("open_task_session처럼 이미 발급된 id를 그대로 기록할 수 있다", () => {
    const registry = new SessionRegistry();
    const record = registry.record("w1", "에이전트가 연 세션", "agent", "mock-session-1");
    expect(record.id).toBe("mock-session-1");
    expect(registry.get("mock-session-1")?.origin).toBe("agent");
  });

  it("빈 제목은 기본 제목으로 대체한다", () => {
    const registry = new SessionRegistry();
    const record = registry.record("w1", "   ", "user");
    expect(record.title).toBe("새 세션");
  });

  it("워크스페이스별로 세션 목록을 조회한다", () => {
    const registry = new SessionRegistry();
    registry.record("w1", "a", "user");
    registry.record("w1", "b", "agent");
    registry.record("w2", "c", "user");
    expect(registry.listForWorkspace("w1")).toHaveLength(2);
    expect(registry.listForWorkspace("w2")).toHaveLength(1);
  });
});
