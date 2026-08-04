import { randomUUID } from "node:crypto";
import type * as acp from "@agentclientprotocol/sdk";
import type {
  AgentHostRequest,
  AgentHostResponse,
  AgentHostEvent,
} from "../shared/agent-host-protocol.js";
import type { JSONValue } from "@speaki-e/protocol";
import { AcpAdapter } from "./acp-adapter.js";
import { CodeEditorQueue, QueueCancelledError } from "./code-editor-queue.js";

interface UtilityParentPort {
  postMessage(message: unknown): void;
  on(event: "message", listener: (event: { data: AgentHostRequest }) => void): void;
}

const parentPort = (process as NodeJS.Process & { parentPort?: UtilityParentPort }).parentPort;
if (!parentPort) throw new Error("Agent Host는 Electron Utility Process로 실행해야 합니다");

const queue = new CodeEditorQueue();
/** permission_request의 requestId -> ACP resolvePermission을 이어서 끝낼 resolve(김민영 W5). */
const pendingPermissions = new Map<string, (response: acp.RequestPermissionResponse) => void>();

function respond(message: AgentHostResponse): void {
  parentPort!.postMessage(message);
}

function emit(event: AgentHostEvent["event"], payload: AgentHostEvent["payload"]): void {
  parentPort!.postMessage({ kind: "event", event, payload } satisfies AgentHostEvent);
}

/**
 * runCodeEditor 요청마다 새 AcpAdapter를 만든다(전에는 모듈 스코프에 하나만 있었다). CodeEditorQueue는
 * 워크스페이스별로만 직렬화하고 서로 다른 워크스페이스는 병렬 실행하므로(4.2), 공유 인스턴스 하나로는
 * onUpdate/resolvePermission이 "지금 이 이벤트가 어느 requestId/workspaceId 것인지" 구분할 수 없었다.
 * 요청마다 만들면 onUpdate/resolvePermission 클로저가 자기 requestId를 들고 있어 안전하게 구분된다.
 */
function createAdapterFor(payload: { requestId: string; workspaceId: string; sessionId: string }): AcpAdapter {
  return new AcpAdapter({
    onUpdate: (update) => emit("code_editor_update", {
      requestId: payload.requestId,
      workspaceId: payload.workspaceId,
      update: JSON.parse(JSON.stringify(update)),
    } as JSONValue),
    resolvePermission: (request) => new Promise<acp.RequestPermissionResponse>((resolve) => {
      const permissionRequestId = randomUUID();
      pendingPermissions.set(permissionRequestId, resolve);
      emit("permission_request", {
        requestId: permissionRequestId,
        workspaceId: payload.workspaceId,
        sessionId: payload.sessionId,
        toolCall: JSON.parse(JSON.stringify(request.toolCall)),
        options: JSON.parse(JSON.stringify(request.options)),
      } as JSONValue);
    }),
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
      case "permissionResponse": {
        const resolve = pendingPermissions.get(message.payload.requestId);
        if (resolve) {
          pendingPermissions.delete(message.payload.requestId);
          resolve(message.payload.response as unknown as acp.RequestPermissionResponse);
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
        pendingPermissions.clear();
        respond({ kind: "response", id: message.id, ok: true, payload: { accepted: true } });
        setImmediate(() => process.exit(0));
        break;
    }
  } catch (error) {
    respond({ kind: "response", id: message.id, ok: false, error: error instanceof Error ? error.message : String(error) });
  }
});

emit("ready", { pid: process.pid });
