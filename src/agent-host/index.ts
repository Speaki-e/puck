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
const adapter = new AcpAdapter({
  onUpdate: (update) => emit("code_editor_update", JSON.parse(JSON.stringify(update)) as JSONValue),
});

function respond(message: AgentHostResponse): void {
  parentPort!.postMessage(message);
}

function emit(event: AgentHostEvent["event"], payload: AgentHostEvent["payload"]): void {
  parentPort!.postMessage({ kind: "event", event, payload } satisfies AgentHostEvent);
}

parentPort.on("message", async ({ data: message }) => {
  try {
    switch (message.method) {
      case "ping":
        respond({ kind: "response", id: message.id, ok: true, payload: { now: message.payload.now, hostNow: Date.now() } });
        break;
      case "runCodeEditor": {
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
        respond({ kind: "response", id: message.id, ok: true, payload: { accepted: true } });
        setImmediate(() => process.exit(0));
        break;
    }
  } catch (error) {
    respond({ kind: "response", id: message.id, ok: false, error: error instanceof Error ? error.message : String(error) });
  }
});

emit("ready", { pid: process.pid });
