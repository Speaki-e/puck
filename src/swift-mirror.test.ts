/**
 * Guards the hand-maintained Swift mirrors against drifting from the TS
 * contract. pet-app copies swift/*.swift verbatim, so a stale mirror ships
 * a wrong contract to a consumer that has no way to notice.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { TOOL_REGISTRY } from "./types/tools.js";

// dist-test/swift-mirror.test.js -> <repo root>/swift/ToolTimeouts.swift
const swiftSource = readFileSync(new URL("../swift/ToolTimeouts.swift", import.meta.url), "utf8");

/** Parses the `"tool": 30,` entries out of ToolTimeouts.bySeconds. */
function parseSwiftTimeouts(source: string): Map<string, number> {
  const body = source.match(/bySeconds:\s*\[String:\s*TimeInterval\]\s*=\s*\[([\s\S]*?)\n\s*\]/);
  assert.ok(body, "could not locate ToolTimeouts.bySeconds in the Swift mirror");
  const entries = new Map<string, number>();
  for (const [, name, seconds] of body[1]!.matchAll(/"([a-z_]+)"\s*:\s*(\d+)/g)) {
    entries.set(name!, Number(seconds));
  }
  return entries;
}

test("ToolTimeouts.swift mirrors every tool's timeoutSec from tools.ts", () => {
  const swift = parseSwiftTimeouts(swiftSource);
  const expected = new Map(TOOL_REGISTRY.map((t) => [t.name, t.timeoutSec]));
  assert.deepEqual(
    Object.fromEntries([...swift].sort()),
    Object.fromEntries([...expected].sort()),
  );
});

test("ToolTimeouts.swift's fallback matches the registry's documented default", () => {
  const fallback = swiftSource.match(/defaultSeconds:\s*TimeInterval\s*=\s*(\d+)/);
  assert.ok(fallback, "could not locate ToolTimeouts.defaultSeconds");
  assert.equal(Number(fallback[1]), 15);
});
