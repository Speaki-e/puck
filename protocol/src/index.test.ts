import { test } from "node:test";
import assert from "node:assert/strict";
import { TOOL_REGISTRY, REQUIRED_CLIPS, isBridgeMessage } from "./index.js";

test("package entry point re-exports the registry, manifest constants, and validator", () => {
  assert.ok(Array.isArray(TOOL_REGISTRY) && TOOL_REGISTRY.length > 0);
  assert.ok(Array.isArray(REQUIRED_CLIPS) && REQUIRED_CLIPS.length > 0);
  assert.equal(isBridgeMessage({ type: "tool_cancel", id: "t1" }), true);
});
