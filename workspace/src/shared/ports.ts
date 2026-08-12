import type { AgentCallbacks, Attachment, Context, JSONValue } from "@speaki-e/protocol";

export interface AgentRuntime {
  run(
    command: string,
    sessionId: string,
    context: Context,
    callbacks: AgentCallbacks,
    attachments?: Attachment[],
    signal?: AbortSignal,
  ): Promise<void>;
}

export interface SecretProvider {
  getClaudeApiKey(): Promise<string | undefined>;
}

export interface ApprovalPort {
  requestApproval(input: {
    runId: string;
    workspaceId: string;
    sessionId: string;
    source: "ai-module" | "acp";
    summary: string;
    options?: JSONValue;
  }): Promise<boolean>;
}

export interface SessionRouterPort {
  route(workspaceId: string, sessionId: string, task: () => Promise<void>): Promise<void>;
}

export interface RunRegistryPort {
  begin(workspaceId: string, sessionId: string): { runId: string; signal: AbortSignal };
  finish(runId: string): void;
  cancel(sessionId: string): boolean;
}
