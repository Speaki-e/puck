import { AsyncLocalStorage } from "node:async_hooks";
import {
  createClient,
  type AiClient,
  type ClientOptions,
  type RunCallbacks,
  type ToolResultInfo,
} from "@speaki-e/ai-module";
import type {
  AgentCallbacks,
  Attachment,
  Context,
  JSONValue,
  ToolExecutionResult,
  ToolExecutor,
  ToolResultErrorCode,
} from "@speaki-e/protocol";
import type { AgentRuntime } from "../shared/ports.js";

type ClientFactory = (options: ClientOptions) => AiClient;

interface ExecutorScope {
  editorLocal: ToolExecutor;
}

export interface AiModuleRuntimeOptions {
  getApiKey(): Promise<string | undefined>;
  getModel(): string;
  getBaseURL?(): string | undefined;
  petAppProxy: ToolExecutor;
  editorLocalFor(sessionId: string, context: Context): ToolExecutor;
  clientFactory?: ClientFactory;
}

/**
 * ai-module v6를 Workspace의 AgentRuntime 포트에 연결한다.
 *
 * ai-module 클라이언트는 세션 히스토리를 인스턴스 내부에 보관하므로 Workspace별로
 * 이 어댑터 인스턴스를 재사용한다. 반면 editorLocal은 sessionId를 캡처해야 하므로
 * 매 run마다 달라진다. AsyncLocalStorage로 run별 실행기를 격리해 서로 다른 세션이
 * 동시에 도구를 호출해도 실행기가 섞이지 않게 한다.
 */
export class AiModuleRuntime implements AgentRuntime {
  private readonly executorScope = new AsyncLocalStorage<ExecutorScope>();
  private clientState?: { key: string; client: AiClient };

  constructor(private readonly options: AiModuleRuntimeOptions) {}

  async run(
    command: string,
    sessionId: string,
    context: Context,
    callbacks: AgentCallbacks,
    attachments?: Attachment[],
    signal?: AbortSignal,
  ): Promise<void> {
    const client = await this.getClient(callbacks);
    if (!client) return;

    const editorLocal = this.options.editorLocalFor(sessionId, context);
    const aiCallbacks: RunCallbacks = {
      onTextChunk: (text) => callbacks.onTextChunk(text),
      onToolCallStart: (call) => callbacks.onToolCallStart(call.id, call.name, toJsonValue(call.input)),
      onToolResult: (result) => forwardToolResult(callbacks, result),
      onApprovalRequired: (summary, resolve) => callbacks.onApprovalRequired(summary, resolve),
      onSessionCreated: (newSessionId, title) => callbacks.onSessionCreated(newSessionId, title),
      onDone: (ok, summary) => callbacks.onDone(ok, summary ?? (ok ? "완료" : "실패")),
    };

    await this.executorScope.run({ editorLocal }, () =>
      client.run(command, sessionId, context, aiCallbacks, attachments, signal),
    );
  }

  private async getClient(callbacks: AgentCallbacks): Promise<AiClient | undefined> {
    const apiKey = await this.options.getApiKey();
    if (!apiKey) {
      callbacks.onDone(false, "Claude API 키가 설정되어 있지 않습니다");
      return undefined;
    }

    const model = this.options.getModel();
    const baseURL = this.options.getBaseURL?.();
    const key = `${apiKey}\u0000${model}\u0000${baseURL ?? ""}`;
    if (this.clientState?.key === key) return this.clientState.client;

    const create = this.options.clientFactory ?? createClient;
    const client = create({
      apiKey,
      model,
      baseURL,
      executors: {
        "pet-app": this.options.petAppProxy,
        workspace: {
          execute: (tool, args, signal) => {
            const scope = this.executorScope.getStore();
            if (!scope) {
              return Promise.resolve({
                ok: false,
                error: "execution_failed",
                detail: "Workspace 실행 컨텍스트를 찾을 수 없습니다",
              });
            }
            return scope.editorLocal.execute(tool, args, signal);
          },
        },
      },
    });
    this.clientState = { key, client };
    return client;
  }
}

function toJsonValue(value: unknown): JSONValue {
  if (value === undefined) return null;
  return JSON.parse(JSON.stringify(value)) as JSONValue;
}

function forwardToolResult(callbacks: AgentCallbacks, result: ToolResultInfo): void {
  let parsed: ToolExecutionResult;
  try {
    parsed = JSON.parse(result.content) as ToolExecutionResult;
  } catch {
    callbacks.onToolResult(result.id, false, undefined, "execution_failed", "ai-module 결과를 해석할 수 없습니다");
    return;
  }

  const rawError = parsed.error as string | undefined;
  const error = normalizeToolError(rawError);
  const detail = rawError && error !== rawError
    ? `${rawError}: ${parsed.detail ?? "도구 실행 실패"}`
    : parsed.detail;
  callbacks.onToolResult(result.id, parsed.ok, parsed.data, error, detail);
}

function normalizeToolError(error: string | undefined): ToolResultErrorCode | undefined {
  if (!error) return undefined;
  if (error === "invalid_input" || error === "not_implemented_yet" || error === "executor_not_available") {
    return "execution_failed";
  }
  return error as ToolResultErrorCode;
}
