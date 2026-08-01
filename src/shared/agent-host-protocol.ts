import type { JSONValue } from "@speaki-e/protocol";

export interface AgentHostRequestMap {
  ping: { now: number };
  runCodeEditor: {
    requestId: string;
    workspaceId: string;
    sessionId: string;
    task: string;
    projectPath: string;
  };
  cancelCodeEditor: { requestId: string };
  shutdown: Record<string, never>;
}

export interface AgentHostResponseMap {
  ping: { now: number; hostNow: number };
  runCodeEditor: JSONValue;
  cancelCodeEditor: { cancelled: boolean };
  shutdown: { accepted: true };
}

export type AgentHostRequest<K extends keyof AgentHostRequestMap = keyof AgentHostRequestMap> = {
  kind: "request";
  id: string;
  method: K;
  payload: AgentHostRequestMap[K];
};

export type AgentHostResponse = {
  kind: "response";
  id: string;
  ok: boolean;
  payload?: JSONValue;
  error?: string;
};

export type AgentHostEvent = {
  kind: "event";
  event: "ready" | "status" | "code_editor_update";
  payload: JSONValue;
};

export type AgentHostMessage = AgentHostRequest | AgentHostResponse | AgentHostEvent;
