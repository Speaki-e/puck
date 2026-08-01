import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";
import type {
  AgentHostEvent,
  AgentHostRequestMap,
  AgentHostResponseMap,
  AgentHostResponse,
} from "../shared/agent-host-protocol.js";

interface PendingRequest {
  resolve(value: unknown): void;
  reject(error: Error): void;
  timer: NodeJS.Timeout;
}

export class AgentHostRpc extends EventEmitter {
  private readonly pending = new Map<string, PendingRequest>();

  constructor(private readonly post: (message: unknown) => void) {
    super();
  }

  request<K extends keyof AgentHostRequestMap>(
    method: K,
    payload: AgentHostRequestMap[K],
    timeoutMs = 30_000,
  ): Promise<AgentHostResponseMap[K]> {
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Agent Host 요청 시간 초과: ${String(method)}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.post({ kind: "request", id, method, payload });
    }) as Promise<AgentHostResponseMap[K]>;
  }

  receive(message: AgentHostResponse | AgentHostEvent): void {
    if (message.kind === "event") {
      this.emit("event", message);
      return;
    }
    const request = this.pending.get(message.id);
    if (!request) return;
    this.pending.delete(message.id);
    clearTimeout(request.timer);
    if (message.ok) request.resolve(message.payload);
    else request.reject(new Error(message.error ?? "Agent Host 요청 실패"));
  }

  failAll(reason: string): void {
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(new Error(reason));
    }
    this.pending.clear();
  }

  get pendingCount(): number {
    return this.pending.size;
  }
}
