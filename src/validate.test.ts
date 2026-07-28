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
  assert.equal(isBridgeMessage({ type: "event", event: "await_approval", summary: "requesting to run rm -rf ./dist" }), true);
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
