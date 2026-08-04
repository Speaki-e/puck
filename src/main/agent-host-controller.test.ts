import { EventEmitter } from "node:events";
import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { JsonlLogger } from "./logger.js";

/**
 * AgentHostController는 실제로는 Electron utilityProcess로 Agent Host를 띄운다. vitest는 Electron
 * 바이너리 밖에서 도는 plain node 프로세스라 "electron" 모듈을 그대로 import하면 utilityProcess가
 * 없다 -- fork()가 이벤트를 내는 가짜 자식 프로세스를 반환하도록 모킹해 재시작 시 상태 이벤트가
 * 순서대로 나가는지만 검증한다(공통 W3, Agent Host 재시작 시 GUI에 복구 상태 전달).
 */
class FakeUtilityProcess extends EventEmitter {
  pid = Math.floor(Math.random() * 100_000);
  postMessage = vi.fn();
  kill = vi.fn(() => {
    setImmediate(() => this.emit("exit", 1));
  });
}

const forkedProcesses: FakeUtilityProcess[] = [];
const fork = vi.fn(() => {
  const child = new FakeUtilityProcess();
  forkedProcesses.push(child);
  setImmediate(() => child.emit("spawn"));
  return child;
});

vi.mock("electron", () => ({
  utilityProcess: { fork: (...args: unknown[]) => fork(...(args as [])) },
}));

function sendReady(child: FakeUtilityProcess): void {
  child.emit("message", { kind: "event", event: "ready", payload: { pid: child.pid } });
}

describe("AgentHostController", () => {
  afterEach(() => {
    forkedProcesses.length = 0;
    fork.mockClear();
  });

  it("spawn 시 준비 중 상태를, ready 수신 시 준비됨 상태를 emit한다", async () => {
    const { AgentHostController } = await import("./agent-host-controller.js");
    const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-agenthost-log-"));
    const controller = new AgentHostController("fake-module-path.js", new JsonlLogger(logs));
    const statuses: string[] = [];
    controller.on("status", (status: string) => statuses.push(status));

    await controller.start();
    const child = forkedProcesses[0]!;
    // fork()의 spawn 이벤트가 setImmediate로 예약돼 있어, ready를 보내기 전에 한 틱 기다려야
    // "AI 기능 준비 중" 상태가 먼저 나간다.
    await new Promise((resolve) => setImmediate(resolve));
    sendReady(child);
    await new Promise((resolve) => setImmediate(resolve));

    expect(statuses).toEqual(["AI 기능 준비 중", "준비됨"]);
  });

  it("Agent Host가 비정상 종료 후 재시작되면 '다시 시작하는 중' -> '준비됨' 순서로 상태를 emit한다", async () => {
    const { AgentHostController } = await import("./agent-host-controller.js");
    const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-agenthost-log-"));
    const controller = new AgentHostController("fake-module-path.js", new JsonlLogger(logs));
    const statuses: string[] = [];
    const exitedEvents: Array<{ code: number; willRestart: boolean }> = [];
    controller.on("status", (status: string) => statuses.push(status));
    controller.on("exited", (event: { code: number; willRestart: boolean }) => exitedEvents.push(event));

    await controller.start();
    const firstChild = forkedProcesses[0]!;
    await new Promise((resolve) => setImmediate(resolve));
    sendReady(firstChild);
    await new Promise((resolve) => setImmediate(resolve));
    expect(statuses).toEqual(["AI 기능 준비 중", "준비됨"]);

    // 비정상 종료 -- agent-host-controller.ts의 handleExit이 1초 뒤 자동 재시작을 예약한다.
    firstChild.emit("exit", 97);
    await new Promise((resolve) => setImmediate(resolve));
    expect(exitedEvents).toEqual([{ code: 97, willRestart: true }]);
    expect(statuses).toEqual(["AI 기능 준비 중", "준비됨", "AI 기능을 다시 시작하는 중"]);

    await new Promise((resolve) => setTimeout(resolve, 1_100));
    expect(forkedProcesses).toHaveLength(2);
    const secondChild = forkedProcesses[1]!;
    sendReady(secondChild);
    await new Promise((resolve) => setImmediate(resolve));

    expect(statuses).toEqual(["AI 기능 준비 중", "준비됨", "AI 기능을 다시 시작하는 중", "AI 기능 준비 중", "준비됨"]);
    expect(controller.pid).toBe(secondChild.pid);

    await controller.stop();
  }, 10_000);
});
