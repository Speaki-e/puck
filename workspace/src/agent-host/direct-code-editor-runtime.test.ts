import { describe, expect, it, vi } from "vitest";

import type { AgentCallbacks, JSONValue, ToolExecutionResult, ToolExecutor } from "@speaki-e/protocol";

import { DirectCodeEditorRuntime } from "./direct-code-editor-runtime.js";

function callbacksSpy(): AgentCallbacks & { done: Array<{ ok: boolean; summary: string }> } {
  const done: Array<{ ok: boolean; summary: string }> = [];
  return {
    done,
    onTextChunk: vi.fn(),
    onToolCallStart: vi.fn(),
    onToolResult: vi.fn(),
    onApprovalRequired: vi.fn(),
    onSessionCreated: vi.fn(),
    onDone: (ok, summary) => void done.push({ ok, summary }),
  } as AgentCallbacks & { done: Array<{ ok: boolean; summary: string }> };
}

function executor(result: ToolExecutionResult): ToolExecutor & { calls: Array<{ tool: string; args: JSONValue }> } {
  const calls: Array<{ tool: string; args: JSONValue }> = [];
  return {
    calls,
    execute: (tool, args) => {
      calls.push({ tool, args });
      return Promise.resolve(result);
    },
  } as ToolExecutor & { calls: Array<{ tool: string; args: JSONValue }> };
}

describe("DirectCodeEditorRuntime", () => {
  it("사용자 입력을 code_editor 한 번으로 실행하고 요약을 agent_done으로 낸다", async () => {
    const tool = executor({ ok: true, data: { summary: "hello.ts에 주석을 추가했습니다" } as unknown as JSONValue });
    const callbacks = callbacksSpy();

    await new DirectCodeEditorRuntime(() => tool).run(
      "hello.ts에 주석 달아줘",
      "s1",
      { projectPath: "/tmp/demo" },
      callbacks,
    );

    expect(tool.calls).toEqual([{ tool: "code_editor", args: { task: "hello.ts에 주석 달아줘" } }]);
    expect(callbacks.done).toEqual([{ ok: true, summary: "hello.ts에 주석을 추가했습니다" }]);
  });

  // 모델이 보낸 project_path를 신뢰하지 않는다는 규칙은 editorLocal 쪽에 있고,
  // 이 런타임은 애초에 인자로 넘기지 않는 것으로 그 규칙을 지킨다.
  it("project_path를 인자로 넘기지 않는다", async () => {
    const tool = executor({ ok: true });
    await new DirectCodeEditorRuntime(() => tool).run("고쳐줘", "s1", { projectPath: "/tmp/demo" }, callbacksSpy());

    expect(tool.calls[0]?.args).not.toHaveProperty("project_path");
  });

  it("실패하면 detail을 요약으로 실어 보낸다 -- 빈 요약은 실패 이유를 지운다", async () => {
    const tool = executor({ ok: false, error: "execution_failed", detail: "ACP가 응답하지 않았습니다" });
    const callbacks = callbacksSpy();

    await new DirectCodeEditorRuntime(() => tool).run("고쳐줘", "s1", { projectPath: "/tmp/demo" }, callbacks);

    expect(callbacks.done).toEqual([{ ok: false, summary: "ACP가 응답하지 않았습니다" }]);
    expect(callbacks.onToolResult).toHaveBeenCalledWith(
      expect.any(String),
      false,
      undefined,
      "execution_failed",
      "ACP가 응답하지 않았습니다",
    );
  });
});
