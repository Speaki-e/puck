import { utilityProcess, type UtilityProcess } from "electron";
import { EventEmitter } from "node:events";
import type { AgentHostEvent, AgentHostRequestMap, AgentHostResponseMap } from "../shared/agent-host-protocol.js";
import { AgentHostRpc } from "./agent-host-rpc.js";
import { JsonlLogger } from "./logger.js";

export class AgentHostController extends EventEmitter {
  private child?: UtilityProcess;
  private rpc?: AgentHostRpc;
  private stopping = false;
  private restartTimer?: NodeJS.Timeout;

  constructor(
    private readonly modulePath: string,
    private readonly logger: JsonlLogger,
  ) {
    super();
  }

  async start(): Promise<void> {
    if (this.child) return;
    this.stopping = false;
    const child = utilityProcess.fork(this.modulePath, [], {
      serviceName: "Workspace Agent Host",
      env: { NODE_ENV: process.env.NODE_ENV ?? "production" },
    });
    this.child = child;
    this.rpc = new AgentHostRpc((message) => child.postMessage(message));
    this.rpc.on("event", (event: AgentHostEvent) => this.emit("event", event));
    child.on("message", (message) => this.rpc?.receive(message as never));
    child.on("spawn", () => {
      void this.logger.write("info", "agent_host_spawned", { pid: child.pid });
      this.emit("status", "AI 기능 준비 중");
    });
    child.on("exit", (code) => this.handleExit(code));
  }

  request<K extends keyof AgentHostRequestMap>(
    method: K,
    payload: AgentHostRequestMap[K],
    timeoutMs?: number,
  ): Promise<AgentHostResponseMap[K]> {
    if (!this.rpc) return Promise.reject(new Error("Agent Host가 실행 중이 아닙니다"));
    return this.rpc.request(method, payload, timeoutMs);
  }

  async stop(): Promise<void> {
    this.stopping = true;
    if (this.restartTimer) clearTimeout(this.restartTimer);
    this.restartTimer = undefined;
    const child = this.child;
    if (!child) return;
    try {
      await this.request("shutdown", {}, 2_000);
    } catch {
      child.kill();
    }
    this.rpc?.failAll("Agent Host가 종료되었습니다");
    this.rpc = undefined;
    this.child = undefined;
  }

  private handleExit(code: number): void {
    this.rpc?.failAll(`Agent Host가 비정상 종료되었습니다 (${code})`);
    this.rpc = undefined;
    this.child = undefined;
    void this.logger.write(code === 0 ? "info" : "error", "agent_host_exited", { code });
    if (this.stopping) return;
    this.emit("status", "AI 기능을 다시 시작하는 중");
    this.restartTimer = setTimeout(() => void this.start(), 1_000);
  }
}
