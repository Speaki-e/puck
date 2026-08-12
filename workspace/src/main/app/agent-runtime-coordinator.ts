import type { Attachment, JSONValue, ToolErrorCode, ToolExecutionResult, ToolExecutor } from "@speaki-e/protocol";
import { createOpenAiCodeEditorExecutor } from "../openai-code-editor.js";
import { workingPathsFromUpdate, type AcpUpdatePayload } from "../../shared/acp-update.js";
import type { AgentHostController } from "../agent-host-controller.js";
import type { EditorGateway } from "../editor-gateway.js";
import type { JsonlLogger } from "../logger.js";
import type { PetBridge } from "../pet-bridge.js";
import { SessionRegistry } from "../session-registry.js";
import { createEditorLocalExecutor } from "../tool-executors.js";
import type { WorkspaceController } from "../workspace-controller.js";
import type { WorkspaceRegistry } from "../workspace-registry.js";

interface AgentRuntimeCoordinatorDeps {
  agentHost: AgentHostController;
  controller: WorkspaceController;
  editorGateway: EditorGateway;
  petBridge: PetBridge;
  registry: WorkspaceRegistry;
  logger: JsonlLogger;
  /** --openai-code-editor: code_editor를 ACP 대신 OpenAI 툴 루프로 실행 (openai-code-editor.ts). */
  openAiCodeEditor?: { apiKey: string; model: string };
}

export interface AgentRuntimeCoordinator {
  handleUserInput(workspaceId: string, sessionId: string, text: string, attachments?: Attachment[]): Promise<void>;
  cancelSession(sessionId: string): Promise<boolean>;
  respondToApproval(approvalId: string, approved: boolean): Promise<boolean>;
  createUserSession(workspaceId: string, title: string): { id: string; title: string };
  rejectPendingApprovals(): void;
}

interface CodeEditorUpdatePayload {
  requestId: string;
  workspaceId: string;
  update: AcpUpdatePayload;
}

interface ToolExecuteRequestPayload {
  requestId: string;
  executorKind: "workspace-direct";
  tool: string;
  args: JSONValue;
  workspaceId: string;
  sessionId: string;
}

/**
 * Main 쪽 AI 실행 경계. workspace는 "무엇을 할지" 판단하지 않는 일반 에디터다(docs/architecture.md
 * "AI 실행 경계" 참고) -- pet-app의 CodeEditorDelegate가 이미 코딩 작업이라고 판단해 보낸
 * user_input을 code_editor 한 번으로 실행하는 것뿐이다. 이 파일은 그 실행을 Agent Host에 RPC로
 * 위임하고, Agent Host가 emit하는 agent_* 이벤트를 petBridge로 옮겨 싣는 얇은 어댑터다.
 * editorLocal/openAiCodeEditor 자체는 그대로 여기 남는다 -- FileService/EditorGateway가 전부
 * Main 전용이라 옮길 수 없기 때문이다(tool_execute_request로 왕복).
 */
export function createAgentRuntimeCoordinator(deps: AgentRuntimeCoordinatorDeps): AgentRuntimeCoordinator {
  const { agentHost, controller, editorGateway, petBridge, registry, logger } = deps;
  const sessionRegistry = new SessionRegistry();
  const codeEditorRequests = new Map<string, { workspaceId: string; sessionId: string }>();
  const toolExecuteAborts = new Map<string, AbortController>();
  /** Agent Host가 비정상 종료됐을 때 agent_done을 못 받은 세션에 실패를 알리기 위한 최소 추적(W3/W7과 동등). */
  const inFlight = new Map<string, { workspaceId: string; sessionId: string }>();

  const editorLocalFor = (workspaceId: string, sessionId: string): ToolExecutor => {
    const workspace = registry.get(workspaceId);
    return createEditorLocalExecutor({
      workspaceId,
      sessionId,
      // 모델이 보낸 project_path는 신뢰하지 않고 현재 Workspace의 실제 경로로 고정한다.
      projectPath: workspace?.realProjectPath ?? "",
      agentHost,
      editorGateway,
      fileServiceFor: (id) => controller.getFileService(id),
      trackCodeEditorRequest: (requestId) => {
        codeEditorRequests.set(requestId, { workspaceId, sessionId });
        return () => codeEditorRequests.delete(requestId);
      },
    });
  };

  /**
   * code_editor를 실제로 수행하는 실행기("workspace-direct" tool_execute_request가 이걸 탄다).
   * 기본은 editorLocal(ACP 경유)이고, --openai-code-editor면 OpenAI 툴 루프로 바꿔 낀다.
   */
  const codeEditorExecutorFor = (workspaceId: string, sessionId: string): ToolExecutor => {
    const openAi = deps.openAiCodeEditor;
    if (!openAi) return editorLocalFor(workspaceId, sessionId);
    return createOpenAiCodeEditorExecutor({
      projectPath: registry.get(workspaceId)?.realProjectPath ?? "",
      fileServiceFor: () => controller.getFileService(workspaceId),
      apiKey: openAi.apiKey,
      model: openAi.model,
    });
  };

  function handleCodeEditorUpdate(payload: CodeEditorUpdatePayload): void {
    const { requestId, workspaceId, update } = payload;
    const context = codeEditorRequests.get(requestId);
    const workspace = registry.get(workspaceId);
    if (workspace?.realProjectPath && update.locations) {
      const paths = workingPathsFromUpdate(workspace.realProjectPath, update);
      controller.sendWorkingPaths(paths);
      editorGateway.broadcastWorkingPaths(workspaceId, paths);
    }
    editorGateway.broadcastAcpUpdate(workspaceId, update as unknown as JSONValue);
    if (update.sessionUpdate === "agent_message_chunk"
      && update.content?.type === "text"
      && update.content.text
      && context) {
      petBridge.sendEvent({
        type: "event",
        workspace_id: workspaceId,
        session_id: context.sessionId,
        event: "text_chunk",
        text: update.content.text,
      });
    }
  }

  async function handleToolExecuteRequest(payload: ToolExecuteRequestPayload): Promise<void> {
    const controller_ = new AbortController();
    toolExecuteAborts.set(payload.requestId, controller_);
    let result: ToolExecutionResult;
    try {
      const executor = codeEditorExecutorFor(payload.workspaceId, payload.sessionId);
      result = await executor.execute(payload.tool, payload.args, controller_.signal);
    } catch (error) {
      result = { ok: false, error: "execution_failed", detail: error instanceof Error ? error.message : String(error) };
    } finally {
      toolExecuteAborts.delete(payload.requestId);
    }
    await agentHost.request("toolExecuteResponse", { requestId: payload.requestId, result: result as unknown as JSONValue }, 5_000).catch((error) => {
      void logger.write("warn", "tool_execute_response_failed", { message: error instanceof Error ? error.message : String(error) });
    });
  }

  function trackInFlight(workspaceId: string, sessionId: string): void {
    inFlight.set(`${workspaceId}::${sessionId}`, { workspaceId, sessionId });
  }

  function untrackInFlight(workspaceId: string, sessionId: string): void {
    inFlight.delete(`${workspaceId}::${sessionId}`);
  }

  agentHost.on("event", (event: { event: string; payload: unknown }) => {
    switch (event.event) {
      case "status":
        controller.sendAgentStatus(JSON.stringify(event.payload));
        break;
      case "code_editor_update":
        handleCodeEditorUpdate(event.payload as CodeEditorUpdatePayload);
        break;
      case "tool_execute_request":
        void handleToolExecuteRequest(event.payload as ToolExecuteRequestPayload);
        break;
      case "tool_execute_cancel": {
        const { requestId } = event.payload as { requestId: string };
        toolExecuteAborts.get(requestId)?.abort();
        break;
      }
      case "agent_thinking": {
        const { workspaceId, sessionId } = event.payload as { workspaceId: string; sessionId: string };
        petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "agent_thinking" });
        break;
      }
      case "agent_text_chunk": {
        const { workspaceId, sessionId, text } = event.payload as { workspaceId: string; sessionId: string; text: string };
        petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "text_chunk", text });
        break;
      }
      case "agent_tool_call": {
        const { workspaceId, sessionId, id, tool, args } = event.payload as {
          workspaceId: string; sessionId: string; id: string; tool: string; args: JSONValue;
        };
        petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "tool_call", id, tool, args });
        break;
      }
      case "agent_tool_result": {
        const { workspaceId, sessionId, id, ok, data, error, detail } = event.payload as {
          workspaceId: string; sessionId: string; id: string; ok: boolean; data?: JSONValue; error?: ToolErrorCode; detail?: string;
        };
        petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "tool_result", id, ok, data, error, detail });
        break;
      }
      case "agent_approval_request": {
        const { approvalId, summary, workspaceId, sessionId } = event.payload as {
          approvalId: string; summary: string; workspaceId: string; sessionId: string;
        };
        petBridge.sendEvent({
          type: "event",
          workspace_id: workspaceId,
          session_id: sessionId,
          event: "await_approval",
          summary,
          approval_id: approvalId,
        });
        break;
      }
      case "agent_session_created": {
        const { workspaceId, sessionId, title } = event.payload as { workspaceId: string; sessionId: string; title: string };
        sessionRegistry.record(workspaceId, title, "agent", sessionId);
        petBridge.send({ type: "session_create", workspace_id: workspaceId, session_id: sessionId, title, origin: "agent" });
        break;
      }
      case "agent_done": {
        const { workspaceId, sessionId, ok, summary } = event.payload as {
          workspaceId: string; sessionId: string; ok: boolean; summary: string;
        };
        untrackInFlight(workspaceId, sessionId);
        petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "agent_done", ok, summary });
        break;
      }
      default:
        break;
    }
  });

  agentHost.on("exited", () => {
    if (!inFlight.size) return;
    const failed = [...inFlight.values()];
    inFlight.clear();
    for (const { workspaceId, sessionId } of failed) {
      petBridge.sendEvent({
        type: "event",
        workspace_id: workspaceId,
        session_id: sessionId,
        event: "agent_done",
        ok: false,
        summary: "Agent Host가 종료되었습니다",
      });
    }
    void logger.write("warn", "active_runs_failed_on_agent_host_exit", { count: failed.length });
  });

  async function handleUserInput(
    workspaceId: string,
    sessionId: string,
    text: string,
    attachments?: Attachment[],
  ): Promise<void> {
    const workspace = registry.get(workspaceId);
    if (!workspace) {
      await logger.write("warn", "user_input_unknown_workspace", { workspaceId });
      return;
    }
    trackInFlight(workspaceId, sessionId);
    try {
      await agentHost.request("runAgent", {
        workspaceId,
        sessionId,
        text,
        attachments: attachments as unknown as JSONValue,
        projectPath: workspace.realProjectPath,
      }, 10_000);
    } catch (error) {
      untrackInFlight(workspaceId, sessionId);
      petBridge.sendEvent({
        type: "event",
        workspace_id: workspaceId,
        session_id: sessionId,
        event: "agent_done",
        ok: false,
        summary: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return {
    handleUserInput,
    cancelSession: (sessionId) => agentHost.request("cancelAgentSession", { sessionId }, 5_000).then((r) => r.cancelled).catch(() => false),
    respondToApproval: (approvalId, approved) => agentHost.request("respondToApproval", { approvalId, approved }, 5_000).then((r) => r.handled).catch(() => false),
    createUserSession: (workspaceId, title) => sessionRegistry.record(workspaceId, title, "user"),
    rejectPendingApprovals: () => {
      void agentHost.request("rejectPendingApprovals", {}, 5_000).catch(() => undefined);
    },
  };
}
