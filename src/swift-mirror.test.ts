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

// dist-test/swift-mirror.test.js -> <repo root>/swift/ToolRegistry.swift
const toolRegistrySource = readFileSync(new URL("../swift/ToolRegistry.swift", import.meta.url), "utf8");

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

/** Parses each `Tool(name: "...", executor: ..., requiresApproval: ..., parameters: [...])` entry. */
function parseSwiftToolRegistry(source: string): Map<string, Map<string, boolean>> {
  const toolRegex = /Tool\(name: "([a-z_]+)",[^\n]*parameters: \[([^\]]*)\]\),/g;
  const result = new Map<string, Map<string, boolean>>();
  for (const match of source.matchAll(toolRegex)) {
    const [, name, paramsBlock] = match;
    const params = new Map<string, boolean>();
    for (const paramMatch of paramsBlock!.matchAll(/Parameter\(name: "([a-z_]+)", type: \.\w+, isRequired: (true|false)\)/g)) {
      params.set(paramMatch[1]!, paramMatch[2] === "true");
    }
    result.set(name!, params);
  }
  return result;
}

test("ToolRegistry.swift mirrors every tool's parameter required-ness from tools.ts", () => {
  const swift = parseSwiftToolRegistry(toolRegistrySource);
  for (const tool of TOOL_REGISTRY) {
    const mirroredParams = swift.get(tool.name);
    assert.ok(mirroredParams, `ToolRegistry.swift is missing tool "${tool.name}"`);
    for (const param of tool.params) {
      assert.equal(
        mirroredParams.get(param.name),
        param.required,
        `${tool.name}.${param.name} required-ness mismatch (tools.ts says ${param.required})`,
      );
    }
  }
});
