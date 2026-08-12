import { utilityProcess, type UtilityProcess } from "electron";
import { EventEmitter } from "node:events";
import type { AgentHostEvent, AgentHostRequestMap, AgentHostResponseMap } from "../shared/agent-host-protocol.js";
import { AgentHostRpc } from "./agent-host-rpc.js";
import { JsonlLogger } from "./logger.js";

export class AgentHostController extends EventEmitter {
  private child?: UtilityProcess;
  private rpc?: AgentHostRpc;
  private stopping = false;
  private ready = false;
  private restartTimer?: NodeJS.Timeout;

  constructor(
    private readonly modulePath: string,
    private readonly logger: JsonlLogger,
    private readonly appPath = process.cwd(),
    private readonly claudeApiKey?: string,
    private readonly directCodeEditor = false,
  ) {
    super();
  }

  async start(): Promise<void> {
    if (this.child) return;
    this.stopping = false;
    this.ready = false;
    const child = utilityProcess.fork(this.modulePath, [], {
      serviceName: "Workspace Agent Host",
      env: {
        NODE_ENV: process.env.NODE_ENV ?? "production",
        WORKSPACE_APP_PATH: this.appPath,
        ...(this.claudeApiKey ? { ANTHROPIC_API_KEY: this.claudeApiKey } : {}),
        // agent-runner.ts가 mock/direct 런타임을 고를지 결정한다(예전엔 Main의
        // agent-runtime-coordinator가 이 판단을 했다).
        ...(process.env.WORKSPACE_MOCK_AI ? { WORKSPACE_MOCK_AI: process.env.WORKSPACE_MOCK_AI } : {}),
        ...(this.directCodeEditor ? { WORKSPACE_DIRECT_CODE_EDITOR: "1" } : {}),
      },
    });
    this.child = child;
    const rpc = new AgentHostRpc((message) => child.postMessage(message));
    this.rpc = rpc;
    rpc.on("event", (event: AgentHostEvent) => {
      if (event.event === "ready") {
        this.ready = true;
        this.emit("ready");
        // spawn 시 "AI 기능 준비 중"(재시작이면 "AI 기능을 다시 시작하는 중")으로 바뀐 상태 텍스트를
        // 정상으로 되돌린다 -- 이게 없으면 재시작 후에도 GUI가 계속 "다시 시작하는 중"에 머문다
        // (공통 W3, Agent Host 재시작 시 GUI에 복구 상태 전달).
        this.emit("status", "준비됨");
      }
      this.emit("event", event);
    });
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
    const execute = () => {
      if (!this.rpc) throw new Error("Agent Host가 실행 중이 아닙니다");
      return this.rpc.request(method, payload, timeoutMs);
    };
    return this.ready
      ? execute()
      : this.waitUntilReady(Math.min(timeoutMs ?? 30_000, 10_000)).then(execute);
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
    this.ready = false;
  }

  get pid(): number | undefined {
    return this.child?.pid;
  }

  private handleExit(child: UtilityProcess, rpc: AgentHostRpc, code: number): void {
    if (this.child !== child || this.rpc !== rpc) return;
    rpc.failAll(`Agent Host가 비정상 종료되었습니다 (${code})`);
    this.rpc = undefined;
    this.child = undefined;
    this.ready = false;
    void this.logger.write(code === 0 ? "info" : "error", "agent_host_exited", { code });
    // SessionRouter/RunRegistry(김민영 W3/W7)가 진행 중이던 ActiveRun을 전부 실패 처리하려면
    // 사람이 읽는 status 문자열이 아니라 명확한 이벤트가 필요해 추가했다.
    this.emit("exited", { code, willRestart: !this.stopping });
    if (this.stopping) return;
    this.emit("status", "AI 기능을 다시 시작하는 중");
    if (this.restartTimer) clearTimeout(this.restartTimer);
    this.restartTimer = setTimeout(() => {
      this.restartTimer = undefined;
      void this.start();
    }, 1_000);
  }

  private waitUntilReady(timeoutMs: number): Promise<void> {
    if (this.ready) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const onReady = () => {
        clearTimeout(timer);
        resolve();
      };
      const timer = setTimeout(() => {
        this.off("ready", onReady);
        reject(new Error("Agent Host 준비 시간 초과"));
      }, timeoutMs);
      this.once("ready", onReady);
    });
  }
}
