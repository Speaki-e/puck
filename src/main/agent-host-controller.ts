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
    private readonly appPath = process.cwd(),
    private readonly claudeApiKey?: string,
  ) {
    super();
  }

  async start(): Promise<void> {
    if (this.child) return;
    this.stopping = false;
    const child = utilityProcess.fork(this.modulePath, [], {
      serviceName: "Workspace Agent Host",
      env: {
        NODE_ENV: process.env.NODE_ENV ?? "production",
        WORKSPACE_APP_PATH: this.appPath,
        ...(this.claudeApiKey ? { ANTHROPIC_API_KEY: this.claudeApiKey } : {}),
      },
    });
    this.child = child;
    const rpc = new AgentHostRpc((message) => child.postMessage(message));
    this.rpc = rpc;
    rpc.on("event", (event: AgentHostEvent) => this.emit("event", event));
    child.on("message", (message) => rpc.receive(message as never));
    child.on("spawn", () => {
      void this.logger.write("info", "agent_host_spawned", { pid: child.pid });
      this.emit("status", "AI 기능 준비 중");
    });
    child.on("exit", (code) => this.handleExit(child, rpc, code));
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

  get pid(): number | undefined {
    return this.child?.pid;
  }

  private handleExit(child: UtilityProcess, rpc: AgentHostRpc, code: number): void {
    if (this.child !== child || this.rpc !== rpc) return;
    rpc.failAll(`Agent Host가 비정상 종료되었습니다 (${code})`);
    this.rpc = undefined;
    this.child = undefined;
    void this.logger.write(code === 0 ? "info" : "error", "agent_host_exited", { code });
    if (this.stopping) return;
    this.emit("status", "AI 기능을 다시 시작하는 중");
    if (this.restartTimer) clearTimeout(this.restartTimer);
    this.restartTimer = setTimeout(() => {
      this.restartTimer = undefined;
      void this.start();
    }, 1_000);
  }
}
