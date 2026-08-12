import { test } from "node:test";
import assert from "node:assert/strict";
import { REQUIRED_CLIPS } from "./avatar-manifest.js";

test("idle is the only required clip (2026-07-29 2D switch -- others, including walk, fall back to idle)", () => {
  assert.deepEqual([...REQUIRED_CLIPS], ["idle"]);
});
