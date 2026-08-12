import type { AgentCallbacks, Attachment, JSONValue, ToolExecutionResult, ToolExecutor } from "@speaki-e/protocol";
import { MockAgentRuntime } from "../mocks/mock-agent-runtime.js";
import type { AgentRuntime } from "../shared/ports.js";
import { createAcpPermissionResolver } from "./acp-permission-bridge.js";
import type { PermissionResolver } from "./acp-adapter.js";
import { AiModuleRuntime } from "./ai-module-runtime.js";
import { DirectCodeEditorRuntime } from "./direct-code-editor-runtime.js";
import { PendingApprovalStore } from "./pending-approval-store.js";
import { cancelActiveRun, failAllActiveRuns } from "./run-cancellation.js";
import { RunRegistry } from "./run-registry.js";
import { SessionRouter } from "./session-router.js";

export type ExecutorKind = "pet-app" | "workspace" | "workspace-direct";

export interface AgentRunnerDeps {
  emit(event: string, payload: JSONValue): void;
  /**
   * petAppProxy/editorLocal이 실제로 무언가를 하려면 Main에 있는 petBridge/FileService/
   * EditorGateway가 필요하다 -- Agent Host는 이 콜백으로 실행을 Main에 위임한다
   * (tool_execute_request/toolExecuteResponse의 왕복은 index.ts가 감춘다).
   */
  executeToolOnMain(
    executorKind: ExecutorKind,
    tool: string,
    args: JSONValue,
    workspaceId: string,
    sessionId: string,
    signal?: AbortSignal,
  ): Promise<ToolExecutionResult>;
  /** Claude API 키/모델은 Main의 SecretStore/SettingsStore가 소유하므로 run마다 다시 물어본다. */
  getRuntimeConfig(): Promise<{ apiKey?: string; model: string }>;
  useMockAiModule: boolean;
  /** --direct-code-editor: ai-module을 건너뛰고 code_editor로 직결 (DirectCodeEditorRuntime). */
  directCodeEditor: boolean;
}

function createToolExecuteProxy(
  deps: AgentRunnerDeps,
  executorKind: ExecutorKind,
  workspaceId: string,
  sessionId: string,
): ToolExecutor {
  return {
    execute: (tool, args, signal) => deps.executeToolOnMain(executorKind, tool, args, workspaceId, sessionId, signal),
  };
}

export interface AgentRunner {
  runAgent(input: {
    workspaceId: string;
    sessionId: string;
    text: string;
    attachments?: Attachment[];
    projectPath?: string;
  }): Promise<void>;
  cancelSession(sessionId: string): boolean;
  respondToApproval(approvalId: string, approved: boolean): boolean;
  rejectPendingApprovals(): void;
  /** acp-adapter.ts의 resolvePermission으로 쓸 리졸버 -- ACP 승인도 ai-module 승인과 같은 저장소를 탄다. */
  permissionResolverFor(payload: { workspaceId: string; sessionId: string }): PermissionResolver;
  /** Agent Host 종료 직전(shutdown RPC): 대기 중이던 실행을 전부 실패 처리하고 agent_done을 보낸다. */
  shutdown(): void;
}

/**
 * ai-module 실행을 소유한다(docs/architecture.md "다음 구조 단계": ai-module과
 * SessionRouter/RunRegistry를 Agent Host로). Main은 이제 사용자 입력 하나를 runAgent 요청
 * 한 번으로 위임하고, 진행 상황은 agent_* 이벤트로 받는다.
 */
export function createAgentRunner(deps: AgentRunnerDeps): AgentRunner {
  const sessionRouter = new SessionRouter();
  const runRegistry = new RunRegistry();

  const pendingApprovals = new PendingApprovalStore({
    emit: ({ approvalId, summary, workspaceId, sessionId }) => {
      deps.emit("agent_approval_request", { approvalId, summary, workspaceId, sessionId } as unknown as JSONValue);
    },
    runRegistry,
  });

  const petAppProxy = createToolExecuteProxy(deps, "pet-app", "", "");
  const aiRuntimes = new Map<string, AiModuleRuntime>();

  const editorLocalFor = (workspaceId: string, sessionId: string): ToolExecutor =>
    createToolExecuteProxy(deps, "workspace", workspaceId, sessionId);

  const editorDirectFor = (workspaceId: string, sessionId: string): ToolExecutor =>
    createToolExecuteProxy(deps, "workspace-direct", workspaceId, sessionId);

  const aiRuntimeFor = (workspaceId: string): AiModuleRuntime => {
    const existing = aiRuntimes.get(workspaceId);
    if (existing) return existing;
    // AiModuleRuntime.getClient()는 getApiKey()를 먼저 await한 뒤 getModel()을 동기로 읽는다
    // (04_ai-module.md 3.4) -- 그 순서를 이용해 한 번의 getRuntimeConfig() 왕복으로 둘 다 받아온다.
    let cachedModel = "claude-sonnet-4-5";
    const created = new AiModuleRuntime({
      getApiKey: async () => {
        const config = await deps.getRuntimeConfig();
        cachedModel = config.model;
        return config.apiKey;
      },
      getModel: () => cachedModel,
      petAppProxy,
      editorLocalFor: (sessionId) => editorLocalFor(workspaceId, sessionId),
    });
    aiRuntimes.set(workspaceId, created);
    return created;
  };

  const sendAgentDone = (input: { workspaceId: string; sessionId: string; ok: boolean; summary: string }): void => {
    deps.emit("agent_done", input as unknown as JSONValue);
  };

  const cancellationDeps = { runRegistry, approvals: pendingApprovals, sendAgentDone };

  async function runAgent(input: {
    workspaceId: string;
    sessionId: string;
    text: string;
    attachments?: Attachment[];
    projectPath?: string;
  }): Promise<void> {
    const { workspaceId, sessionId, text, attachments, projectPath } = input;
    await sessionRouter.route(workspaceId, sessionId, async () => {
      const { runId, signal } = runRegistry.begin(workspaceId, sessionId);
      deps.emit("agent_thinking", { workspaceId, sessionId } as unknown as JSONValue);

      const callbacks: AgentCallbacks = {
        onTextChunk: (chunk) => {
          deps.emit("agent_text_chunk", { workspaceId, sessionId, text: chunk } as unknown as JSONValue);
        },
        onToolCallStart: (id, tool, toolArgs) => {
          if (tool === "code_editor") return;
          deps.emit("agent_tool_call", { workspaceId, sessionId, id, tool, args: toolArgs } as unknown as JSONValue);
        },
        onToolResult: (id, ok, data, error, detail) => {
          const wireError = error === "denied_by_user" ? undefined : error;
          deps.emit("agent_tool_result", { workspaceId, sessionId, id, ok, data, error: wireError, detail } as unknown as JSONValue);
        },
        onApprovalRequired: (summary, resolve) => {
          void pendingApprovals
            .requestApproval({ runId, workspaceId, sessionId, source: "ai-module", summary })
            .then(resolve);
        },
        onSessionCreated: (newSessionId, title) => {
          deps.emit("agent_session_created", { workspaceId, sessionId: newSessionId, title } as unknown as JSONValue);
        },
        onDone: (ok, summary) => {
          if (runRegistry.markDoneSent(runId)) sendAgentDone({ workspaceId, sessionId, ok, summary });
        },
      };

      try {
        const agentRuntime: AgentRuntime = deps.useMockAiModule
          ? new MockAgentRuntime({ petAppProxy, editorLocal: editorLocalFor(workspaceId, sessionId) })
          : deps.directCodeEditor
            ? new DirectCodeEditorRuntime((id) => editorDirectFor(workspaceId, id))
            : aiRuntimeFor(workspaceId);

        await agentRuntime.run(text, sessionId, { projectPath }, callbacks, attachments, signal);
      } catch (error) {
        if (runRegistry.markDoneSent(runId)) {
          sendAgentDone({
            workspaceId,
            sessionId,
            ok: false,
            summary: error instanceof Error ? error.message : String(error),
          });
        }
      } finally {
        runRegistry.finish(runId);
      }
    });
  }

  return {
    runAgent,
    cancelSession: (sessionId) => cancelActiveRun(cancellationDeps, sessionId),
    respondToApproval: (approvalId, approved) => pendingApprovals.respond(approvalId, approved),
    rejectPendingApprovals: () => pendingApprovals.rejectAll(),
    permissionResolverFor: (payload) => {
      // 활성 실행을 workspaceId/sessionId로 찾아 approvalId <-> runId 연결을 유지한다 -- 취소 시
      // cancelActiveRun이 그 실행이 만든 승인만 정확히 거부하려면 이 연결이 필요하다(W7).
      // 매칭되는 실행이 없으면(레이스, 혹은 이미 끝난 실행) 위조 id로 대체해 승인 자체는 계속 흐르게 한다.
      const activeRun = runRegistry.listActive().find(
        (candidate) => candidate.workspaceId === payload.workspaceId && candidate.sessionId === payload.sessionId,
      );
      return createAcpPermissionResolver(pendingApprovals, {
        runId: activeRun?.runId ?? `unlinked-${payload.workspaceId}-${payload.sessionId}`,
        workspaceId: payload.workspaceId,
        sessionId: payload.sessionId,
      });
    },
    shutdown: () => {
      failAllActiveRuns(cancellationDeps, "Agent Host가 종료되었습니다");
    },
  };
}
