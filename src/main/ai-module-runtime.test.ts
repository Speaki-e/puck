import { describe, expect, it, vi } from "vitest";
import type { AiClient, ClientOptions } from "@speaki-e/ai-module";
import type { AgentCallbacks, Context, ToolExecutor } from "@speaki-e/protocol";
import { AiModuleRuntime } from "./ai-module-runtime.js";

function callbacks(events: unknown[]): AgentCallbacks {
  return {
    onTextChunk: (text) => events.push(["text", text]),
    onToolCallStart: (id, tool, args) => events.push(["call", id, tool, args]),
    onToolResult: (id, ok, data, error, detail) => events.push(["result", id, ok, data, error, detail]),
    onApprovalRequired: (summary, resolve) => {
      events.push(["approval", summary]);
      resolve(true);
    },
    onSessionCreated: (sessionId, title) => events.push(["session", sessionId, title]),
    onDone: (ok, summary) => events.push(["done", ok, summary]),
  };
}

function noopExecutor(): ToolExecutor {
  return { execute: async () => ({ ok: true }) };
}

describe("AiModuleRuntime", () => {
  it("v6 콜백과 protocol AgentCallbacks를 양방향 변환한다", async () => {
    const events: unknown[] = [];
    let options: ClientOptions | undefined;
    const fakeClient: AiClient = {
      run: async (_command: string, _sessionId: string, _context: Context, cb) => {
        cb.onTextChunk("안녕");
        cb.onToolCallStart?.({ id: "t1", name: "launch_app", input: { app_name: "Safari" }, executor: "pet-app" });
        const approved = await new Promise<boolean>((resolve) => cb.onApprovalRequired?.("앱 실행", resolve));
        expect(approved).toBe(true);
        cb.onToolResult?.({ id: "t1", name: "launch_app", ok: true, content: '{"ok":true,"data":{"opened":true}}' });
        cb.onSessionCreated?.("s2", "작업 세션");
        cb.onDone(true, "end_turn");
      },
    } as AiClient;
    const factory = vi.fn((input: ClientOptions) => {
      options = input;
      return fakeClient;
    });

    const runtime = new AiModuleRuntime({
      getApiKey: async () => "test-key",
      getModel: () => "test-model",
      petAppProxy: noopExecutor(),
      editorLocalFor: () => noopExecutor(),
      clientFactory: factory,
    });
    await runtime.run("사파리 켜줘", "default", {}, callbacks(events));

    expect(options?.apiKey).toBe("test-key");
    expect(options?.model).toBe("test-model");
    expect(events).toEqual([
      ["text", "안녕"],
      ["call", "t1", "launch_app", { app_name: "Safari" }],
      ["approval", "앱 실행"],
      ["result", "t1", true, { opened: true }, undefined, undefined],
      ["session", "s2", "작업 세션"],
      ["done", true, "end_turn"],
    ]);
  });

  it("같은 설정에서는 클라이언트를 재사용해 ai-module 세션 히스토리가 유지된다", async () => {
    const run = vi.fn(async (...args: unknown[]) => {
      const cb = args[3] as { onDone(ok: boolean, summary?: string): void };
      cb.onDone(true, "end_turn");
    });
    const factory = vi.fn(() => ({ run } as unknown as AiClient));
    const runtime = new AiModuleRuntime({
      getApiKey: async () => "key",
      getModel: () => "model",
      petAppProxy: noopExecutor(),
      editorLocalFor: () => noopExecutor(),
      clientFactory: factory,
    });
    await runtime.run("첫 번째", "default", {}, callbacks([]));
    await runtime.run("두 번째", "default", {}, callbacks([]));
    expect(factory).toHaveBeenCalledTimes(1);
    expect(run).toHaveBeenCalledTimes(2);
  });

  it("동시에 실행되는 세션별 editorLocal을 AsyncLocalStorage로 격리한다", async () => {
    const calls: string[] = [];
    let workspaceExecutor: ToolExecutor | undefined;
    const factory = (options: ClientOptions): AiClient => {
      workspaceExecutor = options.executors.workspace;
      return {
        run: async (_command: string, sessionId: string, _context: Context, cb) => {
          await new Promise((resolve) => setTimeout(resolve, sessionId === "a" ? 10 : 0));
          await workspaceExecutor!.execute("read_file", { path: `${sessionId}.txt` });
          cb.onDone(true, "end_turn");
        },
      } as AiClient;
    };
    const runtime = new AiModuleRuntime({
      getApiKey: async () => "key",
      getModel: () => "model",
      petAppProxy: noopExecutor(),
      editorLocalFor: (sessionId) => ({
        execute: async () => {
          calls.push(sessionId);
          return { ok: true };
        },
      }),
      clientFactory: factory,
    });

    await Promise.all([
      runtime.run("A", "a", {}, callbacks([])),
      runtime.run("B", "b", {}, callbacks([])),
    ]);
    expect(calls.sort()).toEqual(["a", "b"]);
  });

  it("API 키가 없으면 Claude를 만들지 않고 실패 이벤트로 끝낸다", async () => {
    const events: unknown[] = [];
    const factory = vi.fn(() => ({ run: vi.fn() } as unknown as AiClient));
    const runtime = new AiModuleRuntime({
      getApiKey: async () => undefined,
      getModel: () => "model",
      petAppProxy: noopExecutor(),
      editorLocalFor: () => noopExecutor(),
      clientFactory: factory,
    });
    await runtime.run("테스트", "default", {}, callbacks(events));
    expect(factory).not.toHaveBeenCalled();
    expect(events).toEqual([["done", false, "Claude API 키가 설정되어 있지 않습니다"]]);
  });

  it("forwards the configured local Anthropic endpoint to the client", async () => {
    let received: ClientOptions | undefined;
    const runtime = new AiModuleRuntime({
      getApiKey: async () => "test-key",
      getModel: () => "test-model",
      getBaseURL: () => "http://127.0.0.1:8787",
      petAppProxy: noopExecutor(),
      editorLocalFor: () => noopExecutor(),
      clientFactory: (options) => {
        received = options;
        return { run: async () => {} } as AiClient;
      },
    });

    await runtime.run("hello", "default", {}, callbacks([]));

    expect(received?.baseURL).toBe("http://127.0.0.1:8787");
  });
});
