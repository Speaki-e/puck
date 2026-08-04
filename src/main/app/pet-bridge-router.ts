import type { Attachment } from "@speaki-e/protocol";
import { filterValidAttachments, type AttachmentPolicy } from "../attachment-validator.js";
import type { EditorGateway } from "../editor-gateway.js";
import type { JsonlLogger } from "../logger.js";
import type { PetBridge, PetBridgeState } from "../pet-bridge.js";
import type { WorkspaceController } from "../workspace-controller.js";
import type { WorkspaceRegistry } from "../workspace-registry.js";
import type { AgentRuntimeCoordinator } from "./agent-runtime-coordinator.js";

interface PetBridgeRouterDeps {
  bridge: PetBridge;
  registry: WorkspaceRegistry;
  controller: WorkspaceController;
  editorGateway: EditorGateway;
  coordinator: AgentRuntimeCoordinator;
  attachmentPolicy: AttachmentPolicy;
  logger: JsonlLogger;
}

type IncomingBridgeMessage = { type: string; [key: string]: unknown };

function stringField(message: IncomingBridgeMessage, key: string, fallback: string): string {
  const value = message[key];
  return typeof value === "string" ? value : fallback;
}

/** Attach all pet-app state and message routes to a single PetBridge instance. */
export function installPetBridgeRouter(deps: PetBridgeRouterDeps): void {
  const {
    bridge,
    registry,
    controller,
    editorGateway,
    coordinator,
    attachmentPolicy,
    logger,
  } = deps;

  const sendEditorViewStatus = (workspaceId: string): void => {
    const record = registry.get(workspaceId);
    if (!record) return;
    if (record.realProjectPath) {
      bridge.send({ type: "editor_view_ready", workspace_id: workspaceId, url: editorGateway.url(workspaceId) });
    } else {
      bridge.send({ type: "editor_view_unavailable", workspace_id: workspaceId, reason: "no_project_path" });
    }
  };

  controller.on("project-bound", (record: { id: string }) => sendEditorViewStatus(record.id));

  bridge.on("state", (state: PetBridgeState) => {
    controller.sendAgentStatus(`pet-app: ${state}`);
    if (state === "disconnected" || state === "closed") coordinator.rejectPendingApprovals();
    if (state === "connected") {
      for (const record of registry.list()) sendEditorViewStatus(record.id);
    }
  });

  bridge.on("message", (message: IncomingBridgeMessage) => {
    void routeMessage(message).catch((error) => logger.write("warn", "bridge_message_route_failed", {
      type: message.type,
      message: error instanceof Error ? error.message : String(error),
    }));
  });

  bridge.connect();

  async function routeMessage(message: IncomingBridgeMessage): Promise<void> {
    switch (message.type) {
      case "user_input": {
        const workspaceId = stringField(message, "workspace_id", "default");
        const sessionId = stringField(message, "session_id", "default");
        const rawAttachments = Array.isArray(message.attachments)
          ? message.attachments as Attachment[]
          : undefined;
        const attachments = await filterValidAttachments(rawAttachments, attachmentPolicy, logger);
        await coordinator.handleUserInput(
          workspaceId,
          sessionId,
          String(message.text ?? ""),
          attachments.length ? attachments : undefined,
        );
        break;
      }
      case "run_cancel":
        coordinator.cancelSession(stringField(message, "session_id", "default"));
        break;
      case "approval_response":
        coordinator.respondToApproval(
          stringField(message, "approval_id", ""),
          Boolean(message.approved),
        );
        break;
      case "workspace_create_request": {
        const name = stringField(message, "name", "Workspace");
        const projectPath = typeof message.project_path === "string" ? message.project_path : undefined;
        const record = await registry.create(name, projectPath);
        bridge.send({
          type: "workspace_create",
          workspace_id: record.id,
          name: record.name,
          project_path: record.realProjectPath,
        });
        sendEditorViewStatus(record.id);
        break;
      }
      case "session_create_request": {
        const workspaceId = stringField(message, "workspace_id", "default");
        const record = coordinator.createUserSession(
          workspaceId,
          stringField(message, "title", "새 세션"),
        );
        bridge.send({
          type: "session_create",
          workspace_id: workspaceId,
          session_id: record.id,
          title: record.title,
          origin: "user",
        });
        break;
      }
      default:
        break;
    }
  }
}
