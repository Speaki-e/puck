/**
 * Runtime validation for BridgeMessage. The types in events.ts are compile-time
 * only; a line read off the socket is `unknown` until something actually checks
 * its shape. workspace/pet-app should run parsed JSON through isBridgeMessage
 * before trusting it as a BridgeMessage.
 */

import type { BridgeMessage, ToolErrorCode } from "./types/events.js";

const TOOL_ERROR_CODES: ReadonlySet<ToolErrorCode> = new Set([
  "timeout",
  "pet_app_disconnected",
  "permission_denied",
  "not_supported_target",
  "execution_failed",
  "unknown_tool",
  "cancelled",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isJSONValue(value: unknown): boolean {
  if (value === null) return true;
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") return true;
  if (Array.isArray(value)) return value.every(isJSONValue);
  if (isRecord(value)) return Object.values(value).every(isJSONValue);
  return false;
}

function isAttachmentArray(value: unknown): boolean {
  if (!Array.isArray(value)) return false;
  return value.every(
    (a) => isRecord(a) && a.type === "image" && typeof a.path === "string",
  );
}

export function isBridgeMessage(value: unknown): value is BridgeMessage {
  if (!isRecord(value)) return false;

  switch (value.type) {
    case "client_hello":
      return value.role === "workspace" || value.role === "gui";

    case "tool_dispatch":
      return (
        typeof value.id === "string" &&
        typeof value.tool === "string" &&
        "args" in value &&
        isJSONValue(value.args)
      );

    case "tool_cancel":
      return typeof value.id === "string";

    case "tool_result":
      return (
        typeof value.id === "string" &&
        typeof value.ok === "boolean" &&
        (value.data === undefined || isJSONValue(value.data)) &&
        (value.error === undefined || TOOL_ERROR_CODES.has(value.error as ToolErrorCode)) &&
        (value.detail === undefined || typeof value.detail === "string")
      );

    case "event": {
      if (typeof value.workspace_id !== "string" || typeof value.session_id !== "string") return false;
      switch (value.event) {
        case "agent_thinking":
          return true;
        case "text_chunk":
          return typeof value.text === "string";
        case "tool_call":
          return (
            typeof value.id === "string" &&
            typeof value.tool === "string" &&
            (value.args === undefined || isJSONValue(value.args)) &&
            (value.detail === undefined || isJSONValue(value.detail))
          );
        case "tool_result":
          return (
            typeof value.id === "string" &&
            typeof value.ok === "boolean" &&
            (value.data === undefined || isJSONValue(value.data)) &&
            (value.error === undefined || TOOL_ERROR_CODES.has(value.error as ToolErrorCode)) &&
            (value.detail === undefined || typeof value.detail === "string")
          );
        case "await_approval":
          return typeof value.summary === "string" && typeof value.approval_id === "string";
        case "agent_done":
          return typeof value.ok === "boolean" && typeof value.summary === "string";
        default:
          return false;
      }
    }

    case "user_input":
      return (
        typeof value.text === "string" &&
        (value.source === "voice" || value.source === "text") &&
        (value.workspace_id === undefined || typeof value.workspace_id === "string") &&
        (value.session_id === undefined || typeof value.session_id === "string") &&
        (value.attachments === undefined || isAttachmentArray(value.attachments))
      );

    case "workspace_create_request":
      return (
        typeof value.name === "string" &&
        (value.project_path === undefined || typeof value.project_path === "string")
      );

    case "workspace_create":
      return (
        typeof value.workspace_id === "string" &&
        typeof value.name === "string" &&
        (value.project_path === undefined || typeof value.project_path === "string")
      );

    case "session_create_request":
      return typeof value.workspace_id === "string" && typeof value.title === "string";

    case "session_create":
      return (
        typeof value.workspace_id === "string" &&
        typeof value.session_id === "string" &&
        typeof value.title === "string" &&
        (value.origin === "user" || value.origin === "agent")
      );

    case "editor_view_ready":
      return typeof value.workspace_id === "string" && typeof value.url === "string";

    case "editor_view_unavailable":
      return typeof value.workspace_id === "string" && value.reason === "no_project_path";

    case "approval_response":
      return typeof value.approval_id === "string" && typeof value.approved === "boolean";

    case "run_cancel":
      return typeof value.session_id === "string";

    default:
      return false;
  }
}
