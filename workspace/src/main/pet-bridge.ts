import net from "node:net";
import path from "node:path";
import os from "node:os";
import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import {
  TOOL_REGISTRY,
  isBridgeMessage,
  type BridgeEventMessage,
  type BridgeMessage,
  type JSONValue,
  type ToolExecutionResult,
  type ToolResult,
} from "@speaki-e/protocol";
import { JsonlParser } from "./jsonl-parser.js";
import { basenameForLog, JsonlLogger } from "./logger.js";

export interface PetBridgeOptions {
  socketPath?: string;
  reconnectDelaysMs?: number[];
  logger: JsonlLogger;
}

interface PendingDispatch {
  resolve(result: ToolExecutionResult): void;
  timer: NodeJS.Timeout;
  abortCleanup?: () => void;
}

export type PetBridgeState = "disconnected" | "connecting" | "connected" | "closed";

export function defaultBridgeSocketPath(): string {
  if (process.platform === "win32") return "\\\\.\\pipe\\PetAgent-bridge";
  return path.join(os.homedir(), "Library", "Application Support", "PetAgent", "bridge.sock");
}

export class PetBridge extends EventEmitter {
  private readonly socketPath: string;
  private readonly reconnectDelays: number[];
  private readonly parser = new JsonlParser();
  private readonly pending = new Map<string, PendingDispatch>();
  private socket?: net.Socket;
  private reconnectTimer?: NodeJS.Timeout;
  private reconnectAttempt = 0;
  private shouldReconnect = false;
  private currentState: PetBridgeState = "disconnected";

  constructor(private readonly options: PetBridgeOptions) {
    super();
    this.socketPath = options.socketPath ?? defaultBridgeSocketPath();
    this.reconnectDelays = options.reconnectDelaysMs ?? [1_000, 2_000, 4_000, 8_000, 16_000, 30_000];
  }

  get state(): PetBridgeState {
    return this.currentState;
  }

  connect(): void {
    if (this.shouldReconnect || this.currentState === "connected" || this.currentState === "connecting") return;
    this.shouldReconnect = true;
    this.openSocket();
  }

  async close(): Promise<void> {
    this.shouldReconnect = false;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = undefined;
    this.failAll("pet_app_disconnected", "PetBridge가 종료되었습니다");
    const socket = this.socket;
    this.socket = undefined;
    if (socket && !socket.destroyed) {
      await new Promise<void>((resolve) => {
        socket.once("close", () => resolve());
        socket.destroy();
      });
    }
    this.setState("closed");
  }

  dispatch(tool: string, args: JSONValue, signal?: AbortSignal, id = randomUUID()): Promise<ToolExecutionResult> {
    if (signal?.aborted) return Promise.resolve({ ok: false, error: "cancelled", detail: "요청 전에 취소됨" });
    if (this.currentState !== "connected" || !this.socket?.writable) {
      return Promise.resolve({ ok: false, error: "pet_app_disconnected", detail: "pet-app에 연결되지 않았습니다" });
    }
    const timeoutSec = TOOL_REGISTRY.find((entry) => entry.name === tool)?.timeoutSec ?? 15;
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.finish(id, { ok: false, error: "timeout", detail: `${timeoutSec}초 안에 응답하지 않았습니다` });
        this.send({ type: "tool_cancel", id });
      }, timeoutSec * 1_000);
      let abortCleanup: (() => void) | undefined;
      if (signal) {
        const onAbort = () => {
          this.send({ type: "tool_cancel", id });
          this.finish(id, { ok: false, error: "cancelled", detail: "사용자가 작업을 취소했습니다" });
        };
        signal.addEventListener("abort", onAbort, { once: true });
        abortCleanup = () => signal.removeEventListener("abort", onAbort);
      }
      this.pending.set(id, { resolve, timer, abortCleanup });
      this.send({ type: "tool_dispatch", id, tool, args });
      void this.options.logger.write("info", "tool_dispatch", { id, tool });
    });
  }

  cancel(id: string): void {
    this.send({ type: "tool_cancel", id });
    this.finish(id, { ok: false, error: "cancelled", detail: "호출자가 취소했습니다" });
  }

  sendEvent(event: BridgeEventMessage): boolean {
    return this.send(event);
  }

  send(message: BridgeMessage): boolean {
    if (this.currentState !== "connected" || !this.socket?.writable) return false;
    this.socket.write(`${JSON.stringify(message)}\n`, "utf8");
    return true;
  }

  private openSocket(): void {
    if (!this.shouldReconnect) return;
    this.setState("connecting");
    this.parser.reset();
    const socket = net.createConnection(this.socketPath);
    this.socket = socket;
    socket.setNoDelay(true);
    socket.on("connect", () => {
      if (this.socket !== socket) return;
      this.reconnectAttempt = 0;
      this.setState("connected");
      this.send({ type: "client_hello", role: "workspace" });
      // macOS 경로(os.homedir() 하위)는 사용자명을 포함한다(W7 공통 로그 정책 리뷰) -- 마지막 세그먼트만 기록.
      void this.options.logger.write("info", "pet_bridge_connected", { socketPath: basenameForLog(this.socketPath) });
    });
    socket.on("data", (chunk) => this.handleData(chunk));
    socket.on("error", (error) => {
      void this.options.logger.write("warn", "pet_bridge_error", { message: error.message });
    });
    socket.on("close", () => {
      if (this.socket === socket) this.socket = undefined;
      this.parser.reset();
      this.failAll("pet_app_disconnected", "pet-app 연결이 종료되었습니다");
      if (this.shouldReconnect) this.scheduleReconnect();
      else this.setState("closed");
    });
  }

  private handleData(chunk: Buffer): void {
    let values: unknown[];
    try {
      values = this.parser.push(chunk);
    } catch (error) {
      void this.options.logger.write("warn", "invalid_jsonl", { message: error instanceof Error ? error.message : String(error) });
      this.parser.reset();
      return;
    }
    for (const value of values) {
      if (!isBridgeMessage(value)) {
        void this.options.logger.write("warn", "invalid_protocol_message", { value });
        continue;
      }
      if (value.type === "tool_result") this.handleToolResult(value);
      else this.emit("message", value);
    }
  }

  private handleToolResult(message: ToolResult): void {
    if (!this.pending.has(message.id)) {
      void this.options.logger.write("warn", "unknown_tool_result", { id: message.id });
      return;
    }
    this.finish(message.id, {
      ok: message.ok,
      data: message.data,
      error: message.error,
      detail: message.detail,
    });
    void this.options.logger.write("info", "tool_result", { id: message.id, ok: message.ok, error: message.error });
  }

  private finish(id: string, result: ToolExecutionResult): void {
    const request = this.pending.get(id);
    if (!request) return;
    this.pending.delete(id);
    clearTimeout(request.timer);
    request.abortCleanup?.();
    request.resolve(result);
  }

  private failAll(error: "pet_app_disconnected", detail: string): void {
    for (const id of [...this.pending.keys()]) this.finish(id, { ok: false, error, detail });
  }

  private scheduleReconnect(): void {
    this.setState("disconnected");
    if (this.reconnectTimer) return;
    const index = Math.min(this.reconnectAttempt, this.reconnectDelays.length - 1);
    const delay = this.reconnectDelays[index]!;
    this.reconnectAttempt += 1;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = undefined;
      this.openSocket();
    }, delay);
  }

  private setState(state: PetBridgeState): void {
    if (this.currentState === state) return;
    this.currentState = state;
    this.emit("state", state);
  }
}
