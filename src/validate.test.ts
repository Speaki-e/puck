import { test } from "node:test";
import assert from "node:assert/strict";
import { isBridgeMessage } from "./validate.js";

test("accepts a valid tool_dispatch", () => {
  assert.equal(
    isBridgeMessage({ type: "tool_dispatch", id: "t1", tool: "launch_app", args: { app_name: "Safari" } }),
    true,
  );
});

test("accepts a valid tool_cancel", () => {
  assert.equal(isBridgeMessage({ type: "tool_cancel", id: "t1" }), true);
});

test("accepts a valid tool_result with only the required fields", () => {
  assert.equal(isBridgeMessage({ type: "tool_result", id: "t1", ok: true }), true);
});

test("accepts a valid tool_result with data/error/detail", () => {
  assert.equal(
    isBridgeMessage({ type: "tool_result", id: "t1", ok: false, error: "execution_failed", detail: "zsh exited 127" }),
    true,
  );
});

test("accepts run_applescript's bare-string tool_result.data", () => {
  assert.equal(isBridgeMessage({ type: "tool_result", id: "t1", ok: true, data: "some result" }), true);
});

test("rejects a tool_result with an unknown error code", () => {
  assert.equal(isBridgeMessage({ type: "tool_result", id: "t1", ok: false, error: "not_a_real_code" }), false);
});

test("accepts each event kind", () => {
  assert.equal(isBridgeMessage({ type: "event", event: "agent_thinking" }), true);
  assert.equal(isBridgeMessage({ type: "event", event: "tool_call", tool: "code_editor", detail: { path: "src/main.ts" } }), true);
  assert.equal(isBridgeMessage({ type: "event", event: "tool_result", ok: true }), true);
  assert.equal(
    isBridgeMessage({
      type: "event",
      event: "await_approval",
      summary: "requesting to run rm -rf ./dist",
      approval_id: "a1",
      workspace_id: "w1",
      session_id: "s2",
    }),
    true,
  );
  assert.equal(isBridgeMessage({ type: "event", event: "agent_done", ok: true, summary: "3 tests passed" }), true);
});

test("rejects an event with an unknown event name", () => {
  assert.equal(isBridgeMessage({ type: "event", event: "not_a_real_event" }), false);
});

test("accepts valid user_input for both sources", () => {
  assert.equal(isBridgeMessage({ type: "user_input", text: "run this project's tests", source: "voice" }), true);
  assert.equal(isBridgeMessage({ type: "user_input", text: "open README", source: "text" }), true);
});

test("rejects user_input with an invalid source", () => {
  assert.equal(isBridgeMessage({ type: "user_input", text: "x", source: "keyboard" }), false);
});

test("rejects an unknown top-level type", () => {
  assert.equal(isBridgeMessage({ type: "not_a_real_type" }), false);
});

test("rejects non-object values", () => {
  assert.equal(isBridgeMessage(null), false);
  assert.equal(isBridgeMessage(undefined), false);
  assert.equal(isBridgeMessage("tool_dispatch"), false);
  assert.equal(isBridgeMessage(42), false);
  assert.equal(isBridgeMessage([]), false);
});

test("rejects a tool_dispatch missing a required field", () => {
  assert.equal(isBridgeMessage({ type: "tool_dispatch", id: "t1", tool: "launch_app" }), false);
});

// --- sessions/workspaces (2026-07-29, plan/01_protocol.md 3.4) ---

test("accepts user_input without workspace_id/session_id/attachments (they default to \"default\"/absent)", () => {
  assert.equal(isBridgeMessage({ type: "user_input", text: "run tests", source: "voice" }), true);
});

test("accepts user_input with workspace_id/session_id/attachments", () => {
  assert.equal(
    isBridgeMessage({
      type: "user_input",
      text: "look at this",
      source: "text",
      workspace_id: "w1",
      session_id: "s2",
      attachments: [{ type: "image", path: "/tmp/capture.png" }],
    }),
    true,
  );
});

test("rejects user_input with a malformed attachment", () => {
  assert.equal(
    isBridgeMessage({ type: "user_input", text: "x", source: "text", attachments: [{ type: "image" }] }),
    false,
  );
});

test("accepts workspace_create_request and workspace_create", () => {
  assert.equal(
    isBridgeMessage({ type: "workspace_create_request", name: "cat house", project_path: "/tmp/cat-house" }),
    true,
  );
  assert.equal(isBridgeMessage({ type: "workspace_create_request", name: "chat only" }), true);
  assert.equal(
    isBridgeMessage({ type: "workspace_create", workspace_id: "w2", name: "cat house", project_path: "/tmp/cat-house" }),
    true,
  );
});

test("rejects workspace_create missing workspace_id", () => {
  assert.equal(isBridgeMessage({ type: "workspace_create", name: "cat house" }), false);
});

test("accepts session_create_request and session_create for both origins", () => {
  assert.equal(isBridgeMessage({ type: "session_create_request", workspace_id: "w1", title: "new chat" }), true);
  assert.equal(
    isBridgeMessage({ type: "session_create", workspace_id: "w1", session_id: "s2", title: "fix bug", origin: "agent" }),
    true,
  );
  assert.equal(
    isBridgeMessage({ type: "session_create", workspace_id: "w1", session_id: "s3", title: "new chat", origin: "user" }),
    true,
  );
});

test("rejects session_create with an invalid origin", () => {
  assert.equal(
    isBridgeMessage({ type: "session_create", workspace_id: "w1", session_id: "s2", title: "x", origin: "robot" }),
    false,
  );
});

test("accepts editor_view_ready and editor_view_unavailable", () => {
  assert.equal(
    isBridgeMessage({ type: "editor_view_ready", workspace_id: "w1", url: "http://127.0.0.1:53912/editor" }),
    true,
  );
  assert.equal(
    isBridgeMessage({ type: "editor_view_unavailable", workspace_id: "w1", reason: "no_project_path" }),
    true,
  );
});

test("rejects editor_view_unavailable with an unknown reason", () => {
  assert.equal(isBridgeMessage({ type: "editor_view_unavailable", workspace_id: "w1", reason: "gremlins" }), false);
});

test("accepts await_approval with its new routing fields", () => {
  assert.equal(
    isBridgeMessage({
      type: "event",
      event: "await_approval",
      summary: "requesting to run rm -rf ./dist",
      approval_id: "a1",
      workspace_id: "w1",
      session_id: "s2",
    }),
    true,
  );
});

test("rejects await_approval missing the new routing fields", () => {
  assert.equal(
    isBridgeMessage({ type: "event", event: "await_approval", summary: "requesting to run rm -rf ./dist" }),
    false,
  );
});

test("accepts approval_response and run_cancel", () => {
  assert.equal(isBridgeMessage({ type: "approval_response", approval_id: "a1", approved: true }), true);
  assert.equal(isBridgeMessage({ type: "run_cancel", session_id: "s2" }), true);
});

test("rejects approval_response with a non-boolean approved", () => {
  assert.equal(isBridgeMessage({ type: "approval_response", approval_id: "a1", approved: "yes" }), false);
});
