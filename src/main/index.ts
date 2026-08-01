import { app, BrowserWindow, Menu, safeStorage, screen } from "electron";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { JsonlLogger } from "./logger.js";
import { WorkspaceRegistry } from "./workspace-registry.js";
import { WorkspaceController } from "./workspace-controller.js";
import { AgentHostController } from "./agent-host-controller.js";
import { PetBridge } from "./pet-bridge.js";
import { SecretStore } from "./secret-store.js";
import { normalizeWindowState, WindowStateStore } from "./window-state-store.js";
import { resolveClaudeAgentCommand } from "../shared/acp-command.js";
import { workingPathsFromUpdate, type AcpUpdatePayload } from "../shared/acp-update.js";

const isHeadless = process.argv.includes("--headless");

function argumentValue(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function createFallbackWindow(stateStore: WindowStateStore): Promise<() => Promise<void>> {
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
  await window.loadFile(path.join(app.getAppPath(), "dist", "index.html"));
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
  const petBridge = new PetBridge({ socketPath: argumentValue("--bridge-socket"), logger });
  petBridge.on("state", (state: string) => controller.sendAgentStatus(`pet-app: ${state}`));
  petBridge.connect();
  let activeRun: { requestId: string; workspaceId: string; sessionId: string; projectPath: string } | undefined;
  agentHost.on("event", (event: { event: string; payload: unknown }) => {
    if (event.event === "status") controller.sendAgentStatus(JSON.stringify(event.payload));
    if (event.event !== "code_editor_update" || !activeRun) return;
    const payload = event.payload as AcpUpdatePayload;
    if (payload.locations) {
      controller.sendWorkingPaths(workingPathsFromUpdate(activeRun.projectPath, payload));
    }
    if (payload.sessionUpdate === "agent_message_chunk" && payload.content?.type === "text" && payload.content.text) {
      petBridge.sendEvent({
        type: "event",
        workspace_id: activeRun.workspaceId,
        session_id: activeRun.sessionId,
        event: "text_chunk",
        text: payload.content.text,
      });
    }
  });
  const runAgent = async (command: string, workspace: { id: string; realProjectPath?: string }, sessionId: string) => {
    if (!workspace.realProjectPath) throw new Error("프로젝트가 연결되지 않았습니다");
    const requestId = randomUUID();
    activeRun = { requestId, workspaceId: workspace.id, sessionId, projectPath: workspace.realProjectPath };
    petBridge.sendEvent({ type: "event", workspace_id: workspace.id, session_id: sessionId, event: "agent_thinking" });
    void agentHost.request("runCodeEditor", {
      requestId,
      workspaceId: workspace.id,
      sessionId,
      task: command,
      projectPath: workspace.realProjectPath,
    }, 600_000).then((result) => {
      controller.sendAgentStatus(JSON.stringify(result));
      const value = result as { ok?: boolean; summary?: string };
      petBridge.sendEvent({
        type: "event",
        workspace_id: workspace.id,
        session_id: sessionId,
        event: "agent_done",
        ok: value.ok !== false,
        summary: value.summary ?? "작업이 완료되었습니다",
      });
    }).catch((error) => {
      const summary = error instanceof Error ? error.message : String(error);
      controller.sendAgentStatus(summary);
      petBridge.sendEvent({ type: "event", workspace_id: workspace.id, session_id: sessionId, event: "agent_done", ok: false, summary });
    }).finally(() => {
      if (activeRun?.requestId === requestId) {
        activeRun = undefined;
        controller.sendWorkingPaths([]);
      }
    });
    return { requestId };
  };
  const cancelAgent = async (sessionId?: string) => {
    if (!activeRun || (sessionId && activeRun.sessionId !== sessionId)) return false;
    const result = await agentHost.request("cancelCodeEditor", { requestId: activeRun.requestId }, 5_000);
    return result.cancelled;
  };
  controller.setAgentCommands({
    run: (command, workspace) => runAgent(command, workspace, "default"),
    cancel: () => cancelAgent(),
  });
  petBridge.on("message", (message: { type: string; [key: string]: unknown }) => {
    void (async () => {
      if (message.type === "user_input") {
        const workspaceId = typeof message.workspace_id === "string" ? message.workspace_id : "default";
        const sessionId = typeof message.session_id === "string" ? message.session_id : "default";
        const workspace = controller.registry.get(workspaceId);
        if (!workspace) throw new Error(`workspace not found: ${workspaceId}`);
        await runAgent(String(message.text ?? ""), workspace, sessionId);
      } else if (message.type === "run_cancel") {
        await cancelAgent(String(message.session_id ?? "default"));
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
    : await createFallbackWindow(windowStateStore);

  app.on("window-all-closed", () => {
    if (!isHeadless) app.quit();
  });

  let shuttingDown = false;
  app.on("before-quit", (event) => {
    if (shuttingDown) return;
    event.preventDefault();
    shuttingDown = true;
    void Promise.all([petBridge.close(), agentHost.stop(), controller.close(), saveWindowState()])
      .finally(() => app.exit(0));
  });
}

void main().catch((error) => {
  console.error("Workspace Main 시작 실패", error);
  app.exit(1);
});
