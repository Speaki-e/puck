import net from "node:net";
import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { afterEach, describe, expect, it } from "vitest";
import { PetBridge } from "./pet-bridge.js";
import { JsonlLogger } from "./logger.js";
import { PendingApprovalStore } from "./pending-approval-store.js";

const servers: net.Server[] = [];
const bridges: PetBridge[] = [];

function socketPath(): string {
  return process.platform === "win32"
    ? `\\\\.\\pipe\\workspace-test-${randomUUID()}`
    : path.join(os.tmpdir(), `workspace-test-${randomUUID()}.sock`);
}

async function setup(): Promise<{ bridge: PetBridge; peer: net.Socket }> {
  const address = socketPath();
  let resolvePeer!: (socket: net.Socket) => void;
  const peerConnected = new Promise<net.Socket>((resolve) => { resolvePeer = resolve; });
  const server = net.createServer(resolvePeer);
  servers.push(server);
  await new Promise<void>((resolve, reject) => server.listen(address, resolve).once("error", reject));
  const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-petbridge-approval-log-"));
  const bridge = new PetBridge({ socketPath: address, reconnectDelaysMs: [5], logger: new JsonlLogger(logs) });
  bridges.push(bridge);
  const connected = new Promise<void>((resolve) => {
    const onState = (state: string) => {
      if (state !== "connected") return;
      bridge.off("state", onState);
      resolve();
    };
    bridge.on("state", onState);
  });
  bridge.connect();
  const [peer] = await Promise.all([peerConnected, connected]);
  return { bridge, peer };
}

afterEach(async () => {
  await Promise.all(bridges.splice(0).map((bridge) => bridge.close()));
  await Promise.all(servers.splice(0).map((server) => new Promise<void>((resolve) => server.close(() => resolve()))));
});

describe("PendingApprovalStore <-> 실제 PetBridge 연결 종료 통합", () => {
  it("pet-app(bridge.sock) 연결이 끊기면 대기 중이던 승인을 자동 거부한다", async () => {
    const { bridge, peer } = await setup();
    const approvals = new PendingApprovalStore({
      emit: (input) => bridge.sendEvent({
        type: "event",
        workspace_id: input.workspaceId,
        session_id: input.sessionId,
        event: "await_approval",
        summary: input.summary,
        approval_id: input.approvalId,
      }),
    });
    // app/pet-bridge-router.ts가 연결 종료 시 사용하는 것과 동일한 승인 거부 배선(W7 완료 기준).
    bridge.on("state", (state: string) => {
      if (state === "disconnected" || state === "closed") approvals.rejectAll();
    });

    const pending = approvals.requestApproval({
      runId: "r1",
      workspaceId: "w1",
      sessionId: "s1",
      source: "ai-module",
      summary: "빌드 폴더 삭제",
    });
    expect(approvals.pendingCount).toBe(1);

    peer.destroy();
    await expect(pending).resolves.toBe(false);
    expect(approvals.pendingCount).toBe(0);
  });

  it("연결이 살아있는 동안은 승인이 자동 거부되지 않는다", async () => {
    const { bridge, peer } = await setup();
    const approvals = new PendingApprovalStore({ emit: (input) => bridge.sendEvent({
      type: "event",
      workspace_id: input.workspaceId,
      session_id: input.sessionId,
      event: "await_approval",
      summary: input.summary,
      approval_id: input.approvalId,
    }) });
    bridge.on("state", (state: string) => {
      if (state === "disconnected" || state === "closed") approvals.rejectAll();
    });

    approvals.requestApproval({ runId: "r1", workspaceId: "w1", sessionId: "s1", source: "ai-module", summary: "s" });
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(approvals.pendingCount).toBe(1);
    peer.destroy();
  });
});
