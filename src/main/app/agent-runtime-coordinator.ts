import { randomUUID } from "node:crypto";
import type * as acp from "@agentclientprotocol/sdk";
import type { AgentCallbacks, Attachment, JSONValue } from "@speaki-e/protocol";
import { MockAgentRuntime } from "../../mocks/mock-agent-runtime.js";
import { AiModuleRuntime } from "../ai-module-runtime.js";
import { workingPathsFromUpdate, type AcpUpdatePayload } from "../../shared/acp-update.js";
import { createAcpPermissionResolver } from "../acp-permission-bridge.js";
import type { AgentHostController } from "../agent-host-controller.js";
import type { EditorGateway } from "../editor-gateway.js";
import type { JsonlLogger } from "../logger.js";
import { PendingApprovalStore } from "../pending-approval-store.js";
import type { PetBridge } from "../pet-bridge.js";
import { cancelActiveRun, failAllActiveRuns } from "../run-cancellation.js";
import { RunRegistry } from "../run-registry.js";
import { SessionRegistry } from "../session-registry.js";
import { SessionRouter } from "../session-router.js";
import { createEditorLocalExecutor, createPetAppProxyExecutor } from "../tool-executors.js";
import type { WorkspaceController } from "../workspace-controller.js";
import type { WorkspaceRegistry } from "../workspace-registry.js";

interface AgentRuntimeCoordinatorDeps {
  agentHost: AgentHostController;
  controller: WorkspaceController;
  editorGateway: EditorGateway;
  petBridge: PetBridge;
  registry: WorkspaceRegistry;
  logger: JsonlLogger;
  getClaudeApiKey?(): Promise<string | undefined>;
  getModel?(): string;
  useMockAiModule?: boolean;
}

export interface AgentRuntimeCoordinator {
  handleUserInput(workspaceId: string, sessionId: string, text: string, attachments?: Attachment[]): Promise<void>;
  cancelSession(sessionId: string): boolean;
  respondToApproval(approvalId: string, approved: boolean): boolean;
  createUserSession(workspaceId: string, title: string): { id: string; title: string };
  rejectPendingApprovals(): void;
}

interface PermissionRequestPayload {
  requestId: string;
  workspaceId: string;
  sessionId: string;
  toolCall: acp.ToolCallUpdate;
  options: acp.PermissionOption[];
}

interface CodeEditorUpdatePayload {
  requestId: string;
  workspaceId: string;
  update: AcpUpdatePayload;
}

/**
 * Owns the temporary Main-process AI orchestration boundary.
 *
 * SessionRouter/RunRegistry move into Agent Host when the real ai-module package is available;
 * keeping this boundary behind one object makes that migration local instead of touching bootstrap,
 * PetBridge routing, and Electron lifecycle code at the same time.
 */
export function createAgentRuntimeCoordinator(deps: AgentRuntimeCoordinatorDeps): AgentRuntimeCoordinator {
  const { agentHost, controller, editorGateway, petBridge, registry, logger } = deps;
  const sessionRouter = new SessionRouter();
  const runRegistry = new RunRegistry();
  const sessionRegistry = new SessionRegistry();
  const pendingApprovals = new PendingApprovalStore({
    emit: ({ approvalId, summary, workspaceId, sessionId }) => {
      petBridge.sendEvent({
        type: "event",
        workspace_id: workspaceId,
        session_id: sessionId,
        event: "await_approval",
        summary,
        approval_id: approvalId,
      });
    },
    runRegistry,
  });
  const petAppProxy = createPetAppProxyExecutor(petBridge);
  const codeEditorRequests = new Map<string, { workspaceId: string; sessionId: string }>();
  const aiRuntimes = new Map<string, AiModuleRuntime>();

  const editorLocalFor = (workspaceId: string, sessionId: string) => {
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

  const aiRuntimeFor = (workspaceId: string): AiModuleRuntime => {
    const existing = aiRuntimes.get(workspaceId);
    if (existing) return existing;
    const created = new AiModuleRuntime({
      getApiKey: deps.getClaudeApiKey ?? (async () => process.env.ANTHROPIC_API_KEY),
      getModel: deps.getModel ?? (() => "claude-sonnet-4-5"),
      petAppProxy,
      editorLocalFor: (sessionId) => editorLocalFor(workspaceId, sessionId),
    });
    aiRuntimes.set(workspaceId, created);
    return created;
  };

  const sendAgentDone = (input: { workspaceId: string; sessionId: string; ok: boolean; summary: string }) => {
    petBridge.sendEvent({
      type: "event",
      workspace_id: input.workspaceId,
      session_id: input.sessionId,
      event: "agent_done",
      ok: input.ok,
      summary: input.summary,
    });
  };

  const cancellationDeps = { runRegistry, approvals: pendingApprovals, sendAgentDone };

  async function handlePermissionRequest(payload: PermissionRequestPayload): Promise<void> {
    const activeRun = runRegistry.listActive().find(
      (candidate) => candidate.workspaceId === payload.workspaceId && candidate.sessionId === payload.sessionId,
    );
    const resolver = createAcpPermissionResolver(pendingApprovals, {
      runId: activeRun?.runId ?? `unlinked-${payload.workspaceId}-${payload.sessionId}`,
      workspaceId: payload.workspaceId,
      sessionId: payload.sessionId,
    });
    const response = await resolver({
      toolCall: payload.toolCall,
      options: payload.options,
    } as acp.RequestPermissionRequest);

    try {
      await agentHost.request(
        "permissionResponse",
        { requestId: payload.requestId, response: response as unknown as JSONValue },
        30_000,
      );
    } catch (error) {
      await logger.write("warn", "permission_response_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

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

  agentHost.on("event", (event: { event: string; payload: unknown }) => {
    if (event.event === "status") {
      controller.sendAgentStatus(JSON.stringify(event.payload));
    } else if (event.event === "permission_request") {
      void handlePermissionRequest(event.payload as PermissionRequestPayload);
    } else if (event.event === "code_editor_update") {
      handleCodeEditorUpdate(event.payload as CodeEditorUpdatePayload);
    }
  });

  agentHost.on("exited", () => {
    const failed = failAllActiveRuns(cancellationDeps, "Agent Host가 종료되었습니다");
    if (failed.length) {
      void logger.write("warn", "active_runs_failed_on_agent_host_exit", { count: failed.length });
    }
  });

  async function handleUserInput(
    workspaceId: string,
    sessionId: string,
    text: string,
    attachments?: Attachment[],
  ): Promise<void> {
    await sessionRouter.route(workspaceId, sessionId, async () => {
      const workspace = registry.get(workspaceId);
      if (!workspace) {
        await logger.write("warn", "user_input_unknown_workspace", { workspaceId });
        return;
      }

      const { runId, signal } = runRegistry.begin(workspaceId, sessionId);
      petBridge.sendEvent({
        type: "event",
        workspace_id: workspaceId,
        session_id: sessionId,
        event: "agent_thinking",
      });

      const callbacks: AgentCallbacks = {
        onTextChunk: (chunk) => {
          petBridge.sendEvent({
            type: "event",
            workspace_id: workspaceId,
            session_id: sessionId,
            event: "text_chunk",
            text: chunk,
          });
        },
        onToolCallStart: (id, tool, toolArgs) => {
          if (tool === "code_editor") return;
          petBridge.sendEvent({
            type: "event",
            workspace_id: workspaceId,
            session_id: sessionId,
            event: "tool_call",
            id,
            tool,
            args: toolArgs,
          });
        },
        onToolResult: (id, ok, data, error, detail) => {
          const wireError = error === "denied_by_user" ? undefined : error;
          petBridge.sendEvent({
            type: "event",
            workspace_id: workspaceId,
            session_id: sessionId,
            event: "tool_result",
            id,
            ok,
            data,
            error: wireError,
            detail,
          });
        },
        onApprovalRequired: (summary, resolve) => {
          void pendingApprovals
            .requestApproval({ runId, workspaceId, sessionId, source: "ai-module", summary })
            .then(resolve);
        },
        onSessionCreated: (newSessionId, title) => {
          sessionRegistry.record(workspaceId, title, "agent", newSessionId);
          petBridge.send({
            type: "session_create",
            workspace_id: workspaceId,
            session_id: newSessionId,
            title,
            origin: "agent",
          });
        },
        onDone: (ok, summary) => {
          if (runRegistry.markDoneSent(runId)) sendAgentDone({ workspaceId, sessionId, ok, summary });
        },
      };

      try {
        const useMock = deps.useMockAiModule ?? process.env.NODE_ENV === "test";
        const agentRuntime = useMock
          ? new MockAgentRuntime({ petAppProxy, editorLocal: editorLocalFor(workspaceId, sessionId) })
          : aiRuntimeFor(workspaceId);

        await agentRuntime.run(
          text,
          sessionId,
          { projectPath: workspace.realProjectPath },
          callbacks,
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

  controller.setAgentCommands({
    run: (command, workspace) => {
      const requestId = randomUUID();
      void handleUserInput(workspace.id, "default", command).catch((error) => logger.write("warn", "agent_run_failed", {
        workspaceId: workspace.id,
        message: error instanceof Error ? error.message : String(error),
      }));
      return Promise.resolve({ requestId });
    },
    cancel: () => Promise.resolve(cancelActiveRun(cancellationDeps, "default")),
  });

  return {
    handleUserInput,
    cancelSession: (sessionId) => cancelActiveRun(cancellationDeps, sessionId),
    respondToApproval: (approvalId, approved) => pendingApprovals.respond(approvalId, approved),
    createUserSession: (workspaceId, title) => sessionRegistry.record(workspaceId, title, "user"),
    rejectPendingApprovals: () => pendingApprovals.rejectAll(),
  };
}
