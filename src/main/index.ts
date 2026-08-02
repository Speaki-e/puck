import { app, BrowserWindow, Menu, safeStorage, screen } from "electron";
import path from "node:path";
import { randomUUID } from "node:crypto";
import type * as acp from "@agentclientprotocol/sdk";
import type { AgentCallbacks, Attachment, JSONValue } from "@speaki-e/protocol";
import { JsonlLogger } from "./logger.js";
import { WorkspaceRegistry } from "./workspace-registry.js";
import { WorkspaceController } from "./workspace-controller.js";
import { AgentHostController } from "./agent-host-controller.js";
import { PetBridge } from "./pet-bridge.js";
import { SecretStore } from "./secret-store.js";
import { normalizeWindowState, WindowStateStore } from "./window-state-store.js";
import { EditorGateway } from "./editor-gateway.js";
import { SessionRouter } from "./session-router.js";
import { RunRegistry } from "./run-registry.js";
import { PendingApprovalStore } from "./pending-approval-store.js";
import { createAcpPermissionResolver } from "./acp-permission-bridge.js";
import { cancelActiveRun, failAllActiveRuns } from "./run-cancellation.js";
import { createEditorLocalExecutor, createPetAppProxyExecutor } from "./tool-executors.js";
import { MockAgentRuntime } from "../mocks/mock-agent-runtime.js";
import { resolveClaudeAgentCommand } from "../shared/acp-command.js";
import { workingPathsFromUpdate, type AcpUpdatePayload } from "../shared/acp-update.js";

const isHeadless = process.argv.includes("--headless");

function argumentValue(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function createFallbackWindow(stateStore: WindowStateStore, editorUrl: string): Promise<() => Promise<void>> {
  const state = normalizeWindowState(
    await stateStore.load(),
    screen.getAllDisplays().map((display) => display.workArea),
  );
  const window = new BrowserWindow({
    x: state.x,
    y: state.y,
    width: state.width,
    height: state.height,
    minWidth: 880,
    minHeight: 560,
    title: "Workspace",
    frame: process.platform !== "win32",
    autoHideMenuBar: true,
    backgroundColor: "#090909",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(app.getAppPath(), "dist-main", "main", "preload.cjs"),
    },
  });
  let saveTimer: NodeJS.Timeout | undefined;
  const persistBounds = () => {
    const bounds = window.getNormalBounds();
    return stateStore.save({ ...bounds, maximized: window.isMaximized() });
  };
  const saveBounds = () => {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      saveTimer = undefined;
      void persistBounds();
    }, 250);
  };
  window.on("move", saveBounds);
  window.on("resize", saveBounds);
  window.on("maximize", saveBounds);
  window.on("unmaximize", saveBounds);
  window.on("close", () => {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = undefined;
    void persistBounds();
  });
  window.setMenuBarVisibility(false);
  // EditorGateway가 서빙하는 것과 동일한 Editor View 번들을 폴백 창도 그대로 로드한다(W2 완료 기준
  // "폴백 창도 동일 EditorGateway URL 사용") -- contextBridge preload는 로드 URL이 http://든 file://든
  // 그대로 붙으므로, 폴백 창의 window.workspace IPC 경로는 이전과 동일하게 동작한다.
  await window.loadURL(editorUrl);
  if (state.maximized) window.maximize();
  return () => window.isDestroyed() ? stateStore.flush() : persistBounds();
}

async function main(): Promise<void> {
  await app.whenReady();
  Menu.setApplicationMenu(null);
  const logger = new JsonlLogger(path.join(app.getPath("userData"), "logs"));
  const registry = new WorkspaceRegistry(path.join(app.getPath("userData"), "workspaces.json"));
  const secrets = new SecretStore(path.join(app.getPath("userData"), "secrets.json"), safeStorage);
  const windowStateStore = new WindowStateStore(path.join(app.getPath("userData"), "window-state.json"));
  const environmentApiKey = process.env.ANTHROPIC_API_KEY;
  if (environmentApiKey && secrets.available && !(await secrets.get("claudeApiKey"))) {
    await secrets.set("claudeApiKey", environmentApiKey);
  }
  const claudeApiKey = await secrets.get("claudeApiKey") ?? environmentApiKey;
  const controller = new WorkspaceController(registry, logger);
  await controller.initialize(argumentValue("--project"));
  const agentHostModulePath = app.isPackaged
    ? path.join(path.dirname(app.getAppPath()), "app.asar.unpacked", "dist-main", "agent-host", "index.cjs")
    : path.join(app.getAppPath(), "dist-main", "agent-host", "index.cjs");
  const agentHost = new AgentHostController(
    agentHostModulePath,
    logger,
    app.getAppPath(),
    claudeApiKey,
  );
  agentHost.on("status", (status: string) => controller.sendAgentStatus(status));
  await agentHost.start();
  if (process.env.NODE_ENV === "test") {
    (globalThis as typeof globalThis & { __workspaceTest?: Record<string, unknown> }).__workspaceTest = {
      agentHostPid: () => agentHost.pid,
      pingAgentHost: () => agentHost.request("ping", { now: Date.now() }, 2_000),
      crashAgentHost: () => agentHost.request("crashForTest", {}, 2_000).then(() => false, () => true),
      busyAgentHost: (durationMs: number) => agentHost.request("busyForTest", { durationMs }, 5_000),
      resolveAcpCommand: () => resolveClaudeAgentCommand(app.getAppPath()),
    };
  }

  // EditorGateway(W2): Workspace 프로세스당 단일 HTTP/WebSocket 서버. WKWebView와 폴백 창이
  // 같은 URL을 쓰므로, 폴백 창을 만들기 전에 먼저 떠 있어야 한다.
  const editorGateway = new EditorGateway({
    staticRoot: path.join(app.getAppPath(), "dist"),
    logger,
    isKnownWorkspace: (workspaceId) => registry.get(workspaceId) !== undefined,
    fileServiceFor: (workspaceId) => controller.getFileService(workspaceId),
  });
  await editorGateway.start();

  const petBridge = new PetBridge({ socketPath: argumentValue("--bridge-socket"), logger });

  // SessionRouter/RunRegistry/PendingApprovalStore(W3, W7): 사용자 입력 라우팅과 실행·승인 생명주기.
  const sessionRouter = new SessionRouter();
  const runRegistry = new RunRegistry();
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
  /** code_editor의 requestId -> 어느 workspace/session이 시킨 호출인지(AI 이벤트 정규화, W3). */
  const codeEditorRequests = new Map<string, { workspaceId: string; sessionId: string }>();

  function sendAgentDone(input: { workspaceId: string; sessionId: string; ok: boolean; summary: string }): void {
    petBridge.sendEvent({
      type: "event",
      workspace_id: input.workspaceId,
      session_id: input.sessionId,
      event: "agent_done",
      ok: input.ok,
      summary: input.summary,
    });
  }

  async function handlePermissionRequest(payload: {
    requestId: string;
    workspaceId: string;
    sessionId: string;
    toolCall: acp.ToolCallUpdate;
    options: acp.PermissionOption[];
  }): Promise<void> {
    const activeRun = runRegistry.listActive().find(
      (candidate) => candidate.workspaceId === payload.workspaceId && candidate.sessionId === payload.sessionId,
    );
    const resolver = createAcpPermissionResolver(pendingApprovals, {
      runId: activeRun?.runId ?? `unlinked-${payload.workspaceId}-${payload.sessionId}`,
      workspaceId: payload.workspaceId,
      sessionId: payload.sessionId,
    });
    const response = await resolver({ toolCall: payload.toolCall, options: payload.options } as acp.RequestPermissionRequest);
    try {
      await agentHost.request("permissionResponse", { requestId: payload.requestId, response: response as unknown as JSONValue }, 30_000);
    } catch (error) {
      await logger.write("warn", "permission_response_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  agentHost.on("event", (event: { event: string; payload: unknown }) => {
    if (event.event === "status") {
      controller.sendAgentStatus(JSON.stringify(event.payload));
      return;
    }
    if (event.event === "permission_request") {
      void handlePermissionRequest(event.payload as Parameters<typeof handlePermissionRequest>[0]);
      return;
    }
    if (event.event !== "code_editor_update") return;
    const { requestId, workspaceId, update } = event.payload as { requestId: string; workspaceId: string; update: AcpUpdatePayload };
    const context = codeEditorRequests.get(requestId);
    const workspace = registry.get(workspaceId);
    if (workspace?.realProjectPath && update.locations) {
      const paths = workingPathsFromUpdate(workspace.realProjectPath, update);
      controller.sendWorkingPaths(paths);
      editorGateway.broadcastWorkingPaths(workspaceId, paths);
    }
    editorGateway.broadcastAcpUpdate(workspaceId, update as unknown as JSONValue);
    if (update.sessionUpdate === "agent_message_chunk" && update.content?.type === "text" && update.content.text && context) {
      petBridge.sendEvent({
        type: "event",
        workspace_id: workspaceId,
        session_id: context.sessionId,
        event: "text_chunk",
        text: update.content.text,
      });
    }
  });

  // Agent Host가 죽으면 진행 중이던 모든 ActiveRun을 실패 처리한다(W3/W7 완료 기준).
  agentHost.on("exited", () => {
    const failed = failAllActiveRuns(
      { runRegistry, approvals: pendingApprovals, sendAgentDone },
      "Agent Host가 종료되었습니다",
    );
    if (failed.length) void logger.write("warn", "active_runs_failed_on_agent_host_exit", { count: failed.length });
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
      petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "agent_thinking" });

      const editorLocal = createEditorLocalExecutor({
        workspaceId,
        sessionId,
        // 보안 핵심(W6): 모델이 code_editor에 실어 보낸 project_path는 절대 신뢰하지 않고
        // 세션이 속한 워크스페이스의 실제 경로를 강제한다.
        projectPath: workspace.realProjectPath ?? "",
        agentHost,
        editorGateway,
        fileServiceFor: (id) => controller.getFileService(id),
        trackCodeEditorRequest: (requestId) => {
          codeEditorRequests.set(requestId, { workspaceId, sessionId });
          return () => codeEditorRequests.delete(requestId);
        },
      });

      // TODO(ai-module 태그 필요, plan/04_ai-module.md): ai-module 저장소는 아직 실제 태그가
      // 없어(2026-08-02 기준 커밋 하나뿐) 설치할 수 없다. petAppProxy/editorLocal/승인 게이트는
      // 이미 실제 포트 계약(shared/ports.ts)대로 연결돼 있으므로, 태그가 나오면 이 한 줄만
      // 실제 ai-module 생성자 호출로 바꾸면 된다.
      const agentRuntime = new MockAgentRuntime({ petAppProxy, editorLocal });

      const callbacks: AgentCallbacks = {
        onTextChunk: (chunk) => {
          petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "text_chunk", text: chunk });
        },
        onToolCallStart: (id, tool, toolArgs) => {
          // 4.6: code_editor는 예외 -- ACP session/update 분기(위 agentHost.on("event",...))가
          // 이미 편집 경로를 담아 쏘므로 여기서 또 보내면 중복이다.
          if (tool === "code_editor") return;
          petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "tool_call", id, tool, args: toolArgs });
        },
        onToolResult: (id, ok, data, error, detail) => {
          // denied_by_user는 ai-module 내부(승인 게이트)에서만 쓰는 모델 전용 값이라 소켓을
          // 건너지 않는다(protocol events.ts ToolErrorCode 주석) -- wire tool_result에는 실어보내지 않는다.
          const wireError = error === "denied_by_user" ? undefined : error;
          petBridge.sendEvent({ type: "event", workspace_id: workspaceId, session_id: sessionId, event: "tool_result", id, ok, data, error: wireError, detail });
        },
        onApprovalRequired: (summary, resolve) => {
          void pendingApprovals
            .requestApproval({ runId, workspaceId, sessionId, source: "ai-module", summary })
            .then(resolve);
        },
        onSessionCreated: (newSessionId, title) => {
          petBridge.send({ type: "session_create", workspace_id: workspaceId, session_id: newSessionId, title, origin: "agent" });
        },
        onDone: (ok, summary) => {
          if (runRegistry.markDoneSent(runId)) sendAgentDone({ workspaceId, sessionId, ok, summary });
        },
      };

      try {
        await agentRuntime.run(text, sessionId, { projectPath: workspace.realProjectPath }, callbacks, attachments, signal);
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
    cancel: () => Promise.resolve(cancelActiveRun({ runRegistry, approvals: pendingApprovals, sendAgentDone }, "default")),
  });

  // editor_view_ready/unavailable 통지(W4 완료 기준, plan/03_workspace.md 4.7): project_path가
  // 있는 워크스페이스만 EditorGateway URL을 알리고, 없으면 이유를 담아 알린다.
  function sendEditorViewStatus(workspaceId: string): void {
    const record = registry.get(workspaceId);
    if (!record) return;
    if (record.realProjectPath) {
      petBridge.send({ type: "editor_view_ready", workspace_id: workspaceId, url: editorGateway.url(workspaceId) });
    } else {
      petBridge.send({ type: "editor_view_unavailable", workspace_id: workspaceId, reason: "no_project_path" });
    }
  }
  controller.on("project-bound", (record: { id: string }) => sendEditorViewStatus(record.id));

  petBridge.on("state", (state: string) => {
    controller.sendAgentStatus(`pet-app: ${state}`);
    // pet-app 연결 종료 시 대기 중인 승인은 자동 거부한다(W7 완료 기준) -- 응답을 받을 대상이 없다.
    if (state === "disconnected" || state === "closed") pendingApprovals.rejectAll();
    // (재)연결될 때마다 현재 알고 있는 모든 워크스페이스의 editor view 상태를 다시 알려준다.
    if (state === "connected") for (const record of registry.list()) sendEditorViewStatus(record.id);
  });
  petBridge.connect();

  petBridge.on("message", (message: { type: string; [key: string]: unknown }) => {
    void (async () => {
      if (message.type === "user_input") {
        const workspaceId = typeof message.workspace_id === "string" ? message.workspace_id : "default";
        const sessionId = typeof message.session_id === "string" ? message.session_id : "default";
        const attachments = Array.isArray(message.attachments) ? (message.attachments as Attachment[]) : undefined;
        await handleUserInput(workspaceId, sessionId, String(message.text ?? ""), attachments);
      } else if (message.type === "run_cancel") {
        cancelActiveRun({ runRegistry, approvals: pendingApprovals, sendAgentDone }, String(message.session_id ?? "default"));
      } else if (message.type === "approval_response") {
        pendingApprovals.respond(String(message.approval_id ?? ""), Boolean(message.approved));
      }
    })().catch((error) => logger.write("warn", "bridge_message_route_failed", {
      type: message.type,
      message: error instanceof Error ? error.message : String(error),
    }));
  });
  controller.installIpc();
  await logger.write("info", "workspace_started", { headless: isHeadless });

  const saveWindowState = isHeadless
    ? () => windowStateStore.flush()
    : await createFallbackWindow(windowStateStore, editorGateway.url("default"));

  app.on("window-all-closed", () => {
    if (!isHeadless) app.quit();
  });

  let shuttingDown = false;
  app.on("before-quit", (event) => {
    if (shuttingDown) return;
    event.preventDefault();
    shuttingDown = true;
    void Promise.all([
      petBridge.close(),
      agentHost.stop(),
      controller.close(),
      editorGateway.stop(),
      saveWindowState(),
    ]).finally(() => app.exit(0));
  });
}

void main().catch((error) => {
  console.error("Workspace Main 시작 실패", error);
  app.exit(1);
});
