import { app, BrowserWindow } from "electron";
import path from "node:path";
import { JsonlLogger } from "./logger.js";
import { WorkspaceRegistry } from "./workspace-registry.js";
import { WorkspaceController } from "./workspace-controller.js";

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
  controller.installIpc();
  await logger.write("info", "workspace_started", { headless: isHeadless });

  if (!isHeadless) await createFallbackWindow();

  app.on("window-all-closed", () => {
    if (!isHeadless) app.quit();
  });

  app.on("before-quit", () => {
    void controller.close();
  });
}

void main().catch((error) => {
  console.error("Workspace Main 시작 실패", error);
  app.exit(1);
});
