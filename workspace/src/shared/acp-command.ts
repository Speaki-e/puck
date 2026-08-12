import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import path from "node:path";

export function preferUnpackedPath(filePath: string): string {
  const marker = `${path.sep}app.asar${path.sep}`;
  if (!filePath.includes(marker)) return filePath;
  const unpacked = filePath.replace(marker, `${path.sep}app.asar.unpacked${path.sep}`);
  return existsSync(unpacked) ? unpacked : filePath;
}

export function resolveClaudeAgentCommand(appPath: string): { command: string; args: string[] } {
  const requireFromApp = createRequire(path.join(appPath, "package.json"));
  const agentPath = preferUnpackedPath(requireFromApp.resolve("@agentclientprotocol/claude-agent-acp/dist/index.js"));
  return { command: process.execPath, args: [agentPath] };
}
