import { test } from "node:test";
import assert from "node:assert/strict";
import { TOOL_REGISTRY, type ToolDefinition } from "./tools.js";

function requireTool(name: string): ToolDefinition {
  const tool = TOOL_REGISTRY.find((t) => t.name === name);
  assert.ok(tool, `expected a tool named ${name}`);
  return tool;
}

const PET_APP_TOOLS = [
  "launch_app",
  "list_running_apps",
  "get_frontmost_window",
  "find_ui_element",
  "point_at",
  "click_element",
  "run_shell",
  "run_applescript",
];

const WORKSPACE_TOOLS = ["code_editor", "open_in_editor", "read_file"];

/**
 * open_task_session (2026-07-29, plan/01_protocol.md 4/04_ai-module.md 3.7) is
 * the one tool that never dispatches over the socket -- ai-module's tool-use
 * loop handles it inline. It gets its own executor bucket rather than
 * pet-app/workspace for exactly that reason.
 */
const AI_MODULE_TOOLS = ["open_task_session"];

test("registers exactly the 12 tools documented in plan/01_protocol.md section 4", () => {
  const names = TOOL_REGISTRY.map((t) => t.name).sort();
  assert.deepEqual(names, [...PET_APP_TOOLS, ...WORKSPACE_TOOLS, ...AI_MODULE_TOOLS].sort());
});

test("has no duplicate tool names", () => {
  const names = TOOL_REGISTRY.map((t) => t.name);
  assert.equal(new Set(names).size, names.length);
});

test("routes pet-app, workspace, and ai-module tools to the correct executor", () => {
  for (const tool of TOOL_REGISTRY) {
    const expected = PET_APP_TOOLS.includes(tool.name)
      ? "pet-app"
      : AI_MODULE_TOOLS.includes(tool.name)
        ? "ai-module"
        : "workspace";
    assert.equal(tool.executor, expected, `${tool.name} should be executed by ${expected}`);
  }
});

test("every dispatched tool has a positive integer timeout", () => {
  for (const tool of TOOL_REGISTRY) {
    if (AI_MODULE_TOOLS.includes(tool.name)) continue; // never dispatched, no timeout applies
    assert.ok(Number.isInteger(tool.timeoutSec) && tool.timeoutSec > 0, `${tool.name}.timeoutSec`);
  }
});

test("open_task_session never dispatches over the socket", () => {
  const tool = requireTool("open_task_session");
  assert.equal(tool.executor, "ai-module");
  assert.equal(tool.timeoutSec, 0);
  const paramNames = tool.params.map((p) => p.name).sort();
  assert.deepEqual(paramNames, ["brief", "title"]);
});

test("click_element and run_applescript require approval, run_shell has whitelist exceptions", () => {
  assert.equal(requireTool("click_element").approval.kind, "required");
  assert.equal(requireTool("run_applescript").approval.kind, "required");
  assert.equal(requireTool("run_shell").approval.kind, "required_with_whitelist");
  assert.equal(requireTool("launch_app").approval.kind, "not_required");
  assert.equal(requireTool("code_editor").approval.kind, "acp_internal");
});

test("run_applescript is documented as returning a bare string, unlike its object-returning siblings", () => {
  assert.match(requireTool("run_applescript").responseNote, /bare string/i);
  assert.doesNotMatch(requireTool("launch_app").responseNote, /bare string/i);
});

test("find_ui_element takes pid plus at least one of role/title_contains", () => {
  const findUiElement = requireTool("find_ui_element");
  const paramNames = findUiElement.params.map((p) => p.name).sort();
  assert.deepEqual(paramNames, ["pid", "role", "title_contains"]);
  const pid = findUiElement.params.find((p) => p.name === "pid");
  assert.equal(pid?.required, true);
});
