import { describe, expect, it, vi } from "vitest";
import type { AgentCallbacks } from "@speaki-e/protocol";
import { MockAgentRuntime } from "./mock-agent-runtime.js";

function collectCallbacks(): { events: unknown[]; callbacks: AgentCallbacks } {
  const events: unknown[] = [];
  const callbacks: AgentCallbacks = {
    onTextChunk: (text) => { events.push(["text", text]); },
    onToolCallStart: (id, tool, args) => { events.push(["toolStart", id, tool, args]); },
    onToolResult: (id, ok, data, error, detail) => { events.push(["toolResult", id, ok, data, error, detail]); },
    onApprovalRequired: (summary, resolve) => { events.push(["approval", summary, resolve]); },
    onSessionCreated: (sessionId, title) => { events.push(["sessionCreated", sessionId, title]); },
    onDone: (ok, summary) => { events.push(["done", ok, summary]); },
  };
  return { events, callbacks };
}

describe("MockAgentRuntime", () => {
  it("일반 명령은 텍스트 청크 후 완료한다", async () => {
    const runtime = new MockAgentRuntime();
    const { events, callbacks } = collectCallbacks();
    await runtime.run("아무 명령", "s1", {}, callbacks);
    expect(events[0]).toEqual(["text", "Mock 실행: 아무 명령"]);
    expect(events.at(-1)).toEqual(["done", true, "Mock 작업 완료"]);
  });

  it("approve: 스크립트로 승인 왕복을 재현한다", async () => {
    const runtime = new MockAgentRuntime();
    const { events, callbacks } = collectCallbacks();
    const original = callbacks.onApprovalRequired;
    callbacks.onApprovalRequired = (summary, resolve) => {
      original(summary, resolve);
      resolve(true);
    };
    await runtime.run("approve:빌드 폴더 삭제", "s1", {}, callbacks);
    const approvalEvent = events.find((event) => (event as unknown[])[0] === "approval") as [string, string, (approved: boolean) => void];
    expect(approvalEvent[1]).toBe("빌드 폴더 삭제");
    expect(events.at(-1)).toEqual(["done", true, "승인됨"]);
  });

  it("open_task_session: 스크립트로 onSessionCreated를 재현한다", async () => {
    const runtime = new MockAgentRuntime();
    const { events, callbacks } = collectCallbacks();
    await runtime.run("open_task_session:로그인 버그", "s1", {}, callbacks);
    expect(events.some((event) => (event as unknown[])[0] === "sessionCreated" && (event as unknown[])[2] === "로그인 버그")).toBe(true);
  });

  it("tool: 스크립트로 주입된 ToolExecutor를 실제로 호출한다", async () => {
    const editorLocal = { execute: vi.fn().mockResolvedValue({ ok: true, data: { content: "hi" } }) };
    const runtime = new MockAgentRuntime({ editorLocal });
    const { events, callbacks } = collectCallbacks();
    await runtime.run('tool:workspace:read_file {"path":"a.ts"}', "s1", {}, callbacks);
    expect(editorLocal.execute).toHaveBeenCalledWith("read_file", { path: "a.ts" }, undefined);
    expect(events.some((event) => (event as unknown[])[0] === "toolResult" && (event as unknown[])[2] === true)).toBe(true);
    expect(events.at(-1)).toEqual(["done", true, "Mock 작업 완료"]);
  });

  it("executor가 없으면 execution_failed로 응답한다", async () => {
    const runtime = new MockAgentRuntime();
    const { events, callbacks } = collectCallbacks();
    await runtime.run("tool:pet-app:launch_app {}", "s1", {}, callbacks);
    const toolResult = events.find((event) => (event as unknown[])[0] === "toolResult") as unknown[];
    expect(toolResult[2]).toBe(false);
    expect(toolResult[4]).toBe("execution_failed");
  });
});
