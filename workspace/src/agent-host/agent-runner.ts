import type { Attachment, JSONValue, ToolExecutionResult, ToolExecutor } from "@speaki-e/protocol";
import { createAcpPermissionResolver } from "./acp-permission-bridge.js";
import type { PermissionResolver } from "./acp-adapter.js";
import { DirectCodeEditorRuntime } from "./direct-code-editor-runtime.js";
import { PendingApprovalStore } from "./pending-approval-store.js";
import { cancelActiveRun, failAllActiveRuns } from "./run-cancellation.js";
import { RunRegistry } from "./run-registry.js";
import { SessionRouter } from "./session-router.js";

export type ExecutorKind = "workspace-direct";

export interface AgentRunnerDeps {
  emit(event: string, payload: JSONValue): void;
  /**
   * editorDirectFor가 실제로 code_editor를 돌리려면 Main에 있는 agentHost(runCodeEditor RPC)나
   * FileService(OpenAI 대체 경로)가 필요하다 -- Agent Host는 이 콜백으로 실행을 Main에 위임한다
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
  /** acp-adapter.ts의 resolvePermission으로 쓸 리졸버. */
  permissionResolverFor(payload: { workspaceId: string; sessionId: string }): PermissionResolver;
  /** Agent Host 종료 직전(shutdown RPC): 대기 중이던 실행을 전부 실패 처리하고 agent_done을 보낸다. */
  shutdown(): void;
}

/**
 * 2026-08-12, byeolki: "workspace는 일반 에디터고, 모든 AI 처리는 puckclient가 함." ai-module
 * 실행 루프(SessionRouter/RunRegistry를 Agent Host로 옮긴 직전 판)는 걷어냈다 -- workspace는 이제
 * "무엇을 할지" 판단하지 않고, pet-app의 CodeEditorDelegate(Puck/Agent/CodeEditorDelegate.swift)가
 * 이미 코딩 작업이라고 판단해서 보낸 user_input 하나를 code_editor 한 번으로 곧장 실행하기만 한다
 * (예전의 --direct-code-editor 모드가 유일한 경로가 됨). SessionRouter(세션당 직렬화)와
 * RunRegistry(취소/ActiveRun 추적)는 이 단일 실행에도 여전히 의미가 있어 남겨뒀다. petAppProxy와
 * ai-module 전용 승인 경로는 삭제 -- pet-app 도구 호출은 전부 pet-app 자신의 AgentRunner.swift가
 * 처리하고 workspace를 거치지 않는다.
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

  const editorDirectFor = (workspaceId: string, sessionId: string): ToolExecutor =>
    createToolExecuteProxy(deps, "workspace-direct", workspaceId, sessionId);

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

      try {
        const runtime = new DirectCodeEditorRuntime((id) => editorDirectFor(workspaceId, id));
        await runtime.run(
          text,
          sessionId,
          { projectPath },
          {
            onTextChunk: (chunk) => {
              deps.emit("agent_text_chunk", { workspaceId, sessionId, text: chunk } as unknown as JSONValue);
            },
            onToolCallStart: (id, tool, toolArgs) => {
              if (tool === "code_editor") return;
              deps.emit("agent_tool_call", { workspaceId, sessionId, id, tool, args: toolArgs } as unknown as JSONValue);
            },
            onToolResult: (id, ok, data, error, detail) => {
              deps.emit("agent_tool_result", { workspaceId, sessionId, id, ok, data, error, detail } as unknown as JSONValue);
            },
            onApprovalRequired: (_summary, resolve) => resolve(false),
            onSessionCreated: () => {},
            onDone: (ok, summary) => {
              if (runRegistry.markDoneSent(runId)) sendAgentDone({ workspaceId, sessionId, ok, summary });
            },
          },
          attachments,
          signal,
        );
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
