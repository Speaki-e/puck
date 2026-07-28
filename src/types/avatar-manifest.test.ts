import { test } from "node:test";
import assert from "node:assert/strict";
import { REQUIRED_CLIPS } from "./avatar-manifest.js";

test("idle and walk are the only required clips (others fall back to idle)", () => {
  assert.deepEqual([...REQUIRED_CLIPS].sort(), ["idle", "walk"]);
});
