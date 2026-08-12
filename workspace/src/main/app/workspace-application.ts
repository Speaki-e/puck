import { app, Menu, safeStorage } from "electron";
import { realpath } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import type { AttachmentPolicy } from "../attachment-validator.js";
import { AgentHostController } from "../agent-host-controller.js";
import { EditorGateway } from "../editor-gateway.js";
import { JsonlLogger } from "../logger.js";
import { PetBridge } from "../pet-bridge.js";
import { SecretStore } from "../secret-store.js";
import { SettingsController } from "../settings-controller.js";
import { SettingsStore } from "../settings-store.js";
import { WindowStateStore } from "../window-state-store.js";
import { WorkspaceController } from "../workspace-controller.js";
import { WorkspaceRegistry } from "../workspace-registry.js";
import { createAgentRuntimeCoordinator } from "./agent-runtime-coordinator.js";
import { createFallbackWindow } from "./fallback-window.js";
import { installPetBridgeRouter } from "./pet-bridge-router.js";
import { parseRuntimeOptions } from "./runtime-options.js";
import { installAgentHostTestHooks, installEditorGatewayTestHooks } from "./test-hooks.js";

function agentHostModulePath(): string {
  return app.isPackaged
    ? path.join(path.dirname(app.getAppPath()), "app.asar.unpacked", "dist-main", "agent-host", "index.cjs")
    : path.join(app.getAppPath(), "dist-main", "agent-host", "index.cjs");
}

async function createAttachmentPolicy(): Promise<AttachmentPolicy> {
  // macOS /tmp is commonly a symlink; normalize it before containment checks.
  return { allowedDirectories: [await realpath(os.tmpdir())] };
}

/** Composition root for Electron Main. Domain behavior belongs in the modules it wires together. */
export async function startWorkspaceApplication(): Promise<void> {
  const options = parseRuntimeOptions();
  await app.whenReady();
  Menu.setApplicationMenu(null);

  const userData = app.getPath("userData");
  const logger = new JsonlLogger(path.join(userData, "logs"));
  const registry = new WorkspaceRegistry(path.join(userData, "workspaces.json"));
  const secrets = new SecretStore(path.join(userData, "secrets.json"), safeStorage);
  const windowStateStore = new WindowStateStore(path.join(userData, "window-state.json"));
  const settingsStore = new SettingsStore(path.join(userData, "settings.json"));
  const attachmentPolicy = await createAttachmentPolicy();

  await settingsStore.load();
  logger.setMinLevel(settingsStore.current.logLevel);

  const environmentApiKey = process.env.ANTHROPIC_API_KEY;
  if (environmentApiKey && secrets.available && !(await secrets.get("claudeApiKey"))) {
    await secrets.set("claudeApiKey", environmentApiKey);
  }
  const claudeApiKey = await secrets.get("claudeApiKey") ?? environmentApiKey;

  const controller = new WorkspaceController(
    registry,
    logger,
    () => settingsStore.current.fileSizeLimitBytes,
  );
  await controller.initialize(options.projectPath);

  const settingsController = new SettingsController(
    settingsStore,
    secrets,
    registry,
    windowStateStore,
    logger,
    (updated) => logger.setMinLevel(updated.logLevel),
  );
  settingsController.installIpc();

  const agentHost = new AgentHostController(
    agentHostModulePath(),
    logger,
    app.getAppPath(),
    claudeApiKey,
  );
  agentHost.on("status", (status: string) => controller.sendAgentStatus(status));
  await agentHost.start();
  installAgentHostTestHooks(agentHost);

  const editorGateway = new EditorGateway({
    staticRoot: path.join(app.getAppPath(), "dist"),
    logger,
    isKnownWorkspace: (workspaceId) => registry.get(workspaceId) !== undefined,
    fileServiceFor: (workspaceId) => controller.getFileService(workspaceId),
  });
  await editorGateway.start();
  installEditorGatewayTestHooks(editorGateway);

  const petBridge = new PetBridge({ socketPath: options.bridgeSocket, logger });
  const coordinator = createAgentRuntimeCoordinator({
    agentHost,
    controller,
    editorGateway,
    petBridge,
    registry,
    logger,
    // 키가 없으면 플래그만으로는 켜지 않는다 -- 켜진 척하고 매 편집마다 401을
    // 받느니, 기본 경로(ACP)로 남아 있는 편이 낫다.
    openAiCodeEditor: options.openAiCodeEditor && process.env.OPENAI_API_KEY
      ? { apiKey: process.env.OPENAI_API_KEY, model: process.env.OPENAI_MODEL || "gpt-4o" }
      : undefined,
  });
  installPetBridgeRouter({
    bridge: petBridge,
    registry,
    controller,
    editorGateway,
    coordinator,
    attachmentPolicy,
    logger,
  });

  controller.installIpc();
  await logger.write("info", "workspace_started", { headless: options.headless });

  const saveWindowState = options.headless
    ? () => windowStateStore.flush()
    : await createFallbackWindow(windowStateStore, editorGateway.url("default"));

  app.on("window-all-closed", () => {
    if (!options.headless) app.quit();
  });

  let shuttingDown = false;
  app.on("before-quit", (event) => {
    if (shuttingDown) return;
    event.preventDefault();
    shuttingDown = true;
    settingsController.close();
    void Promise.all([
      petBridge.close(),
      agentHost.stop(),
      controller.close(),
      editorGateway.stop(),
      saveWindowState(),
    ]).finally(() => app.exit(0));
  });
}
