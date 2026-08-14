import { randomUUID } from "node:crypto";
import type {
  AgentHostRequest,
  AgentHostResponse,
  AgentHostEvent,
} from "../shared/agent-host-protocol.js";
import type { Attachment, JSONValue, ToolExecutionResult } from "@speaki-e/protocol";
import { AcpAdapter } from "./acp-adapter.js";
import { CodeEditorQueue, QueueCancelledError } from "./code-editor-queue.js";
import { createAgentRunner, type ExecutorKind } from "./agent-runner.js";
import type { CodingAgentKind } from "../shared/acp-command.js";

interface UtilityParentPort {
  postMessage(message: unknown): void;
  on(event: "message", listener: (event: { data: AgentHostRequest }) => void): void;
}

const parentPort = (process as NodeJS.Process & { parentPort?: UtilityParentPort }).parentPort;
if (!parentPort) throw new Error("Agent Host는 Electron Utility Process로 실행해야 합니다");

const queue = new CodeEditorQueue();

function respond(message: AgentHostResponse): void {
  parentPort!.postMessage(message);
}

function emit(event: AgentHostEvent["event"], payload: AgentHostEvent["payload"]): void {
  parentPort!.postMessage({ kind: "event", event, payload } satisfies AgentHostEvent);
}

interface PendingMainCall<T> {
  resolve(value: T): void;
  reject(error: Error): void;
  timer: NodeJS.Timeout;
}

/**
 * Main에 뭔가를 위임하고(이벤트) 답을 기다리는(요청) 왕복 하나를 만든다 -- 요청마다 새 requestId를
 * 먼저 만들고, 그 id로 payload를 구성하도록 호출자에게 넘겨준다(payload 안에 자기 id를 실어야 하므로).
 */
function callMain<T>(
  event: AgentHostEvent["event"],
  buildPayload: (requestId: string) => JSONValue,
  pending: Map<string, PendingMainCall<T>>,
  timeoutMs: number,
): Promise<T> {
  const requestId = randomUUID();
  const result = new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error(`Main 응답 시간 초과: ${event}`));
    }, timeoutMs);
    pending.set(requestId, { resolve, reject, timer });
  });
  emit(event, buildPayload(requestId));
  return result;
}

const toolExecutePending = new Map<string, PendingMainCall<ToolExecutionResult>>();

const agentRunner = createAgentRunner({
  emit,
  executeToolOnMain: (executorKind: ExecutorKind, tool, args, workspaceId, sessionId, signal) => {
    let requestIdForAbort: string | undefined;
    const result = callMain<ToolExecutionResult>(
      "tool_execute_request",
      (requestId) => {
        requestIdForAbort = requestId;
        return { requestId, executorKind, tool, args, workspaceId, sessionId } as unknown as JSONValue;
      },
      toolExecutePending,
      600_000,
    );
    const onAbort = () => { if (requestIdForAbort) emit("tool_execute_cancel", { requestId: requestIdForAbort } as unknown as JSONValue); };
    signal?.addEventListener("abort", onAbort, { once: true });
    return result.finally(() => signal?.removeEventListener("abort", onAbort));
  },
});

/**
 * runCodeEditor 요청마다 새 AcpAdapter를 만든다(전에는 모듈 스코프에 하나만 있었다). CodeEditorQueue는
 * 워크스페이스별로만 직렬화하고 서로 다른 워크스페이스는 병렬 실행하므로(4.2), 공유 인스턴스 하나로는
 * onUpdate/resolvePermission이 "지금 이 이벤트가 어느 requestId/workspaceId 것인지" 구분할 수 없었다.
 * 요청마다 만들면 onUpdate/resolvePermission 클로저가 자기 requestId를 들고 있어 안전하게 구분된다.
 */
function createAdapterFor(payload: { requestId: string; workspaceId: string; sessionId: string; agentKind?: CodingAgentKind }): AcpAdapter {
  return new AcpAdapter({
    agentKind: payload.agentKind,
    onUpdate: (update) => emit("code_editor_update", {
      requestId: payload.requestId,
      workspaceId: payload.workspaceId,
      update: JSON.parse(JSON.stringify(update)),
    } as JSONValue),
    resolvePermission: agentRunner.permissionResolverFor({ workspaceId: payload.workspaceId, sessionId: payload.sessionId }),
  });
}

parentPort.on("message", async ({ data: message }) => {
  try {
    switch (message.method) {
      case "ping":
        respond({ kind: "response", id: message.id, ok: true, payload: { now: message.payload.now, hostNow: Date.now() } });
        break;
      case "runCodeEditor": {
        const adapter = createAdapterFor(message.payload);
        const run = queue.enqueue({
          requestId: message.payload.requestId,
          workspaceId: message.payload.workspaceId,
          execute: (signal) => {
            emit("status", { state: "running", requestId: message.payload.requestId });
            return adapter.run({ ...message.payload, signal });
          },
        });
        const position = queue.position(message.payload.requestId);
        if (position && position > 0) emit("status", { state: "queued", requestId: message.payload.requestId, position });
        try {
          const result = await run;
          respond({ kind: "response", id: message.id, ok: true, payload: result as unknown as JSONValue });
        } catch (error) {
          if (error instanceof QueueCancelledError) {
            respond({ kind: "response", id: message.id, ok: true, payload: { ok: false, summary: "중단됨", changedFiles: [], error: "cancelled" } });
          } else {
            throw error;
          }
        }
        break;
      }
      case "cancelCodeEditor":
        respond({ kind: "response", id: message.id, ok: true, payload: { cancelled: queue.cancel(message.payload.requestId) } });
        break;
      case "runAgent": {
        const payload = message.payload;
        void agentRunner
          .runAgent({
            workspaceId: payload.workspaceId,
            sessionId: payload.sessionId,
            text: payload.text,
            attachments: payload.attachments as unknown as Attachment[] | undefined,
            projectPath: payload.projectPath,
          })
          .catch(() => undefined);
        respond({ kind: "response", id: message.id, ok: true, payload: { accepted: true } });
        break;
      }
      case "cancelAgentSession":
        respond({ kind: "response", id: message.id, ok: true, payload: { cancelled: agentRunner.cancelSession(message.payload.sessionId) } });
        break;
      case "respondToApproval":
        respond({
          kind: "response",
          id: message.id,
          ok: true,
          payload: { handled: agentRunner.respondToApproval(message.payload.approvalId, message.payload.approved) },
        });
        break;
      case "rejectPendingApprovals":
        agentRunner.rejectPendingApprovals();
        respond({ kind: "response", id: message.id, ok: true, payload: { accepted: true } });
        break;
      case "toolExecuteResponse": {
        const pending = toolExecutePending.get(message.payload.requestId);
        if (pending) {
          toolExecutePending.delete(message.payload.requestId);
          clearTimeout(pending.timer);
          pending.resolve(message.payload.result as unknown as ToolExecutionResult);
        }
        respond({ kind: "response", id: message.id, ok: true, payload: { accepted: true } });
        break;
      }
      case "crashForTest":
        if (process.env.NODE_ENV !== "test") throw new Error("테스트 환경에서만 사용할 수 있습니다");
        setImmediate(() => process.exit(97));
        break;
      case "busyForTest": {
        if (process.env.NODE_ENV !== "test") throw new Error("테스트 환경에서만 사용할 수 있습니다");
        const startedAt = Date.now();
        while (Date.now() - startedAt < Math.min(message.payload.durationMs, 2_000)) {
          Math.sqrt(Math.random());
        }
        respond({ kind: "response", id: message.id, ok: true, payload: { elapsedMs: Date.now() - startedAt } });
        break;
      }
      case "shutdown":
        queue.cancelAll();
        agentRunner.shutdown();
        respond({ kind: "response", id: message.id, ok: true, payload: { accepted: true } });
        setImmediate(() => process.exit(0));
        break;
    }
  } catch (error) {
    respond({ kind: "response", id: message.id, ok: false, error: error instanceof Error ? error.message : String(error) });
  }
});

emit("ready", { pid: process.pid });
