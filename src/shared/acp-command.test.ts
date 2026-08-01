import path from "node:path";
import { describe, expect, it } from "vitest";
import { resolveClaudeAgentCommand } from "./acp-command.js";

describe("resolveClaudeAgentCommand", () => {
  it("앱 기준 경로에서 Claude Agent ACP 진입점을 찾는다", () => {
    const result = resolveClaudeAgentCommand(process.cwd());
    expect(result.command).toBe(process.execPath);
    expect(result.args[0]).toContain(path.join("@agentclientprotocol", "claude-agent-acp", "dist", "index.js"));
  });
});
