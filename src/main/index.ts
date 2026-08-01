import { app, BrowserWindow } from "electron";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { JsonlLogger } from "./logger.js";
import { WorkspaceRegistry } from "./workspace-registry.js";
import { WorkspaceController } from "./workspace-controller.js";
import { AgentHostController } from "./agent-host-controller.js";
import { PetBridge } from "./pet-bridge.js";

const isHeadless = process.argv.includes("--headless");

function argumentValue(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function createFallbackWindow(): Promise<void> {
  const window = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 880,
    minHeight: 560,
    title: "Workspace",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(app.getAppPath(), "dist-main", "main", "preload.cjs"),
    },
  });
  await window.loadFile(path.join(app.getAppPath(), "dist", "index.html"));
}

async function main(): Promise<void> {
  await app.whenReady();
  const logger = new JsonlLogger(path.join(app.getPath("userData"), "logs"));
  const registry = new WorkspaceRegistry(path.join(app.getPath("userData"), "workspaces.json"));
  const controller = new WorkspaceController(registry, logger);
  await controller.initialize(argumentValue("--project"));
  const agentHost = new AgentHostController(
    path.join(app.getAppPath(), "dist-main", "agent-host", "index.cjs"),
    logger,
    app.getAppPath(),
  );
  agentHost.on("status", (status: string) => controller.sendAgentStatus(status));
  agentHost.on("event", (event: { event: string; payload: unknown }) => {
    if (event.event === "status") controller.sendAgentStatus(JSON.stringify(event.payload));
  });
  await agentHost.start();
  const petBridge = new PetBridge({ socketPath: argumentValue("--bridge-socket"), logger });
  petBridge.on("state", (state: string) => controller.sendAgentStatus(`pet-app: ${state}`));
  petBridge.connect();
  let activeRequestId: string | undefined;
  controller.setAgentCommands({
    run: async (command, workspace) => {
      const requestId = randomUUID();
      activeRequestId = requestId;
      void agentHost.request("runCodeEditor", {
        requestId,
        workspaceId: workspace.id,
        sessionId: "default",
        task: command,
        projectPath: workspace.realProjectPath!,
      }, 600_000).then((result) => controller.sendAgentStatus(JSON.stringify(result)))
        .catch((error) => controller.sendAgentStatus(error instanceof Error ? error.message : String(error)))
        .finally(() => {
          if (activeRequestId === requestId) activeRequestId = undefined;
        });
      return { requestId };
    },
    cancel: async () => {
      if (!activeRequestId) return false;
      const result = await agentHost.request("cancelCodeEditor", { requestId: activeRequestId }, 5_000);
      return result.cancelled;
    },
  });
  controller.installIpc();
  await logger.write("info", "workspace_started", { headless: isHeadless });

  if (!isHeadless) await createFallbackWindow();

  app.on("window-all-closed", () => {
    if (!isHeadless) app.quit();
  });

  app.on("before-quit", () => {
    void petBridge.close();
    void agentHost.stop();
    void controller.close();
  });
}

void main().catch((error) => {
  console.error("Workspace Main 시작 실패", error);
  app.exit(1);
});
