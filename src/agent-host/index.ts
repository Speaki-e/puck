import type { MessagePort } from "node:worker_threads";
import type {
  AgentHostRequest,
  AgentHostResponse,
  AgentHostEvent,
} from "../shared/agent-host-protocol.js";

const parentPort = (process as NodeJS.Process & { parentPort?: MessagePort }).parentPort;
if (!parentPort) throw new Error("Agent Host는 Electron Utility Process로 실행해야 합니다");

function respond(message: AgentHostResponse): void {
  parentPort!.postMessage(message);
}

function emit(event: AgentHostEvent["event"], payload: AgentHostEvent["payload"]): void {
  parentPort!.postMessage({ kind: "event", event, payload } satisfies AgentHostEvent);
}

parentPort.on("message", async (message: AgentHostRequest) => {
  try {
    switch (message.method) {
      case "ping":
        respond({ kind: "response", id: message.id, ok: true, payload: { now: message.payload.now, hostNow: Date.now() } });
        break;
      case "runCodeEditor":
        emit("status", { state: "running", requestId: message.payload.requestId });
        respond({
          kind: "response",
          id: message.id,
          ok: true,
          payload: { ok: true, summary: `Mock Agent Host: ${message.payload.task}`, changedFiles: [] },
        });
        break;
      case "cancelCodeEditor":
        respond({ kind: "response", id: message.id, ok: true, payload: { cancelled: false } });
        break;
      case "shutdown":
        respond({ kind: "response", id: message.id, ok: true, payload: { accepted: true } });
        setImmediate(() => process.exit(0));
        break;
    }
  } catch (error) {
    respond({ kind: "response", id: message.id, ok: false, error: error instanceof Error ? error.message : String(error) });
  }
});

emit("ready", { pid: process.pid });
