import path from "node:path";
import { describe, expect, it } from "vitest";
import { resolveAgentCommand, resolveClaudeAgentCommand } from "./acp-command.js";

describe("resolveClaudeAgentCommand", () => {
  it("앱 기준 경로에서 Claude Agent ACP 진입점을 찾는다", () => {
    const result = resolveClaudeAgentCommand(process.cwd());
    expect(result.command).toBe(process.execPath);
    expect(result.args[0]).toContain(path.join("@agentclientprotocol", "claude-agent-acp", "dist", "index.js"));
  });
});

describe("resolveAgentCommand", () => {
  it("claude 종류에 대해 claude-agent-acp 진입점을 찾는다", () => {
    const result = resolveAgentCommand("claude", process.cwd());
    expect(result.command).toBe(process.execPath);
    expect(result.args[0]).toContain(path.join("@agentclientprotocol", "claude-agent-acp", "dist", "index.js"));
  });

  it("codex 종류에 대해 codex-acp 진입점을 찾는다", () => {
    const result = resolveAgentCommand("codex", process.cwd());
    expect(result.command).toBe(process.execPath);
    expect(result.args[0]).toContain(path.join("@agentclientprotocol", "codex-acp", "dist", "index.js"));
  });
});
