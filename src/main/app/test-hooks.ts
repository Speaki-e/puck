import { app } from "electron";
import type { AgentHostController } from "../agent-host-controller.js";
import type { EditorGateway } from "../editor-gateway.js";
import { resolveClaudeAgentCommand } from "../../shared/acp-command.js";

interface WorkspaceTestHooks {
  agentHostPid(): number | undefined;
  pingAgentHost(): Promise<unknown>;
  crashAgentHost(): Promise<boolean>;
  busyAgentHost(durationMs: number): Promise<unknown>;
  resolveAcpCommand(): ReturnType<typeof resolveClaudeAgentCommand>;
  editorGatewayUrl?(workspaceId: string): string;
}

type TestGlobal = typeof globalThis & { __workspaceTest?: WorkspaceTestHooks };

export function installAgentHostTestHooks(agentHost: AgentHostController): void {
  if (process.env.NODE_ENV !== "test") return;
  (globalThis as TestGlobal).__workspaceTest = {
    agentHostPid: () => agentHost.pid,
    pingAgentHost: () => agentHost.request("ping", { now: Date.now() }, 2_000),
    crashAgentHost: () => agentHost.request("crashForTest", {}, 2_000).then(() => false, () => true),
    busyAgentHost: (durationMs) => agentHost.request("busyForTest", { durationMs }, 5_000),
    resolveAcpCommand: () => resolveClaudeAgentCommand(app.getAppPath()),
  };
}

export function installEditorGatewayTestHooks(editorGateway: EditorGateway): void {
  if (process.env.NODE_ENV !== "test") return;
  const hooks = (globalThis as TestGlobal).__workspaceTest;
  if (hooks) hooks.editorGatewayUrl = (workspaceId) => editorGateway.url(workspaceId);
}
