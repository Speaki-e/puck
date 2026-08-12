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
   * Main -> Agent Host: 사용자 입력 하나를 DirectCodeEditorRuntime(code_editor 위임)로 실행한다.
   * SessionRouter/RunRegistry가 이제 Agent Host에 있으므로(docs/architecture.md "다음 구조
   * 단계"), 이 요청 하나가 예전 AgentRuntimeCoordinator.handleUserInput 전체를 대신한다.
   * 진행 상황(텍스트/도구 호출/승인 등)은 agent_* 이벤트로 스트리밍되고, 이 요청은 실행이
   * 완전히 끝났을 때만 resolve된다.
   */
  runAgent: {
    workspaceId: string;
    sessionId: string;
    text: string;
    attachments?: JSONValue;
    projectPath?: string;
  };
  /** Main -> Agent Host: session_id로 진행 중인 실행을 취소한다(예전 RunRegistry.cancel). */
  cancelAgentSession: { sessionId: string };
  /** Main -> Agent Host: pet-app의 approval_response를 대기 중인 승인에 연결한다. ACP의
   * request_permission과 ai-module의 onApprovalRequired 둘 다 같은 approval_id 경로로
   * 들어오므로(PendingApprovalStore) 이 요청 하나로 둘 다 처리된다. */
  respondToApproval: { approvalId: string; approved: boolean };
  /** Main -> Agent Host: pet-app 연결 종료 시 대기 중인 모든 승인을 거부한다. */
  rejectPendingApprovals: Record<string, never>;
  /**
   * Main -> Agent Host: "tool_execute_request" 이벤트(editorLocal 실행 요청)에 대한
   * 결과를 돌려준다. Agent Host 혼자서는 petBridge나 FileService에 닿을 수 없으므로 Main이
   * 실제로 실행하고 결과만 돌려준다.
   */
  toolExecuteResponse: { requestId: string; result: JSONValue };
}

export interface AgentHostResponseMap {
  ping: { now: number; hostNow: number };
  runCodeEditor: JSONValue;
  cancelCodeEditor: { cancelled: boolean };
  crashForTest: { accepted: true };
  busyForTest: { elapsedMs: number };
  shutdown: { accepted: true };
  runAgent: { accepted: true };
  cancelAgentSession: { cancelled: boolean };
  respondToApproval: { handled: boolean };
  rejectPendingApprovals: { accepted: true };
  toolExecuteResponse: { accepted: true };
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
   * agent_thinking/agent_text_chunk/agent_tool_call/agent_tool_result/agent_approval_request/
   * agent_session_created/agent_done: 예전에는 AgentCallbacks를 Main이 직접 구현해 받던
   * 것들이다. 이제 그 콜백을 부르는 실행(DirectCodeEditorRuntime)이 Agent Host에 있으므로, 같은
   * 정보를 이벤트로 내보내고 Main은 petBridge로 그대로 옮겨 싣기만 한다.
   *
   * tool_execute_request/tool_execute_cancel: editorLocal(code_editor/open_in_editor/read_file)이
   * 실제로 무언가를 하려면 Main에 있는 petBridge/FileService/EditorGateway가 필요하다. Agent
   * Host는 이 이벤트로 실행을 위임하고, Main은 toolExecuteResponse로 결과를 돌려준다. 실행 중
   * 취소(signal abort)는 tool_execute_cancel로 알린다(응답을 기다리지 않는 fire-and-forget).
   */
  event:
    | "ready"
    | "status"
    | "code_editor_update"
    | "agent_thinking"
    | "agent_text_chunk"
    | "agent_tool_call"
    | "agent_tool_result"
    | "agent_approval_request"
    | "agent_session_created"
    | "agent_done"
    | "tool_execute_request"
    | "tool_execute_cancel";
  payload: JSONValue;
};

export type AgentHostMessage = AgentHostRequest | AgentHostResponse | AgentHostEvent;
