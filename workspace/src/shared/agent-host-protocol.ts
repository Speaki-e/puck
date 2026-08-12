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
  crashForTest: Record<string, never>;
  busyForTest: { durationMs: number };
  shutdown: Record<string, never>;
  /**
   * Main -> Agent Host: "permission_request" 이벤트로 넘어온 ACP request_permission에 대한 답을
   * 돌려준다(김민영 W5 -- 승인 브리지는 Main의 PendingApprovalStore에서만 결정할 수 있으므로
   * Agent Host 혼자서는 resolvePermission을 끝낼 수 없다). response는
   * acp.RequestPermissionResponse를 JSON으로 그대로 실은 것이다.
   */
  permissionResponse: { requestId: string; response: JSONValue };
}

export interface AgentHostResponseMap {
  ping: { now: number; hostNow: number };
  runCodeEditor: JSONValue;
  cancelCodeEditor: { cancelled: boolean };
  crashForTest: { accepted: true };
  busyForTest: { elapsedMs: number };
  shutdown: { accepted: true };
  permissionResponse: { accepted: true };
}

export type AgentHostRequest<K extends keyof AgentHostRequestMap = keyof AgentHostRequestMap> =
  K extends keyof AgentHostRequestMap
    ? { kind: "request"; id: string; method: K; payload: AgentHostRequestMap[K] }
    : never;

export type AgentHostResponse = {
  kind: "response";
  id: string;
  ok: boolean;
  payload?: JSONValue;
  error?: string;
};

export type AgentHostEvent = {
  kind: "event";
  /**
   * permission_request(김민영 W5): Agent Host -> Main. ACP의 request_permission이 걸렸을 때
   * PendingApprovalStore로 라우팅하기 위해 발화한다 -- Main은 permissionResponse 요청으로 답한다.
   */
  event: "ready" | "status" | "code_editor_update" | "permission_request";
  payload: JSONValue;
};

export type AgentHostMessage = AgentHostRequest | AgentHostResponse | AgentHostEvent;
