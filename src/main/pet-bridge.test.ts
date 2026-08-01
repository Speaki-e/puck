import net from "node:net";
import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { afterEach, describe, expect, it } from "vitest";
import { PetBridge } from "./pet-bridge.js";
import { JsonlLogger } from "./logger.js";

const servers: net.Server[] = [];
const bridges: PetBridge[] = [];

function socketPath(): string {
  return process.platform === "win32"
    ? `\\\\.\\pipe\\workspace-test-${randomUUID()}`
    : path.join(os.tmpdir(), `workspace-test-${randomUUID()}.sock`);
}

async function setup(handler: (socket: net.Socket) => void): Promise<{ bridge: PetBridge; address: string }> {
  const address = socketPath();
  let resolveAccepted!: () => void;
  const accepted = new Promise<void>((resolve) => { resolveAccepted = resolve; });
  const server = net.createServer((socket) => {
    handler(socket);
    resolveAccepted();
  });
  servers.push(server);
  await new Promise<void>((resolve, reject) => server.listen(address, resolve).once("error", reject));
  const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-petbridge-log-"));
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
  await Promise.all([connected, accepted]);
  return { bridge, address };
}

afterEach(async () => {
  await Promise.all(bridges.splice(0).map((bridge) => bridge.close()));
  await Promise.all(servers.splice(0).map((server) => new Promise<void>((resolve) => server.close(() => resolve()))));
});

describe("PetBridge", () => {
  it("handshake 후 dispatch와 분할 result를 매칭한다", async () => {
    const lines: string[] = [];
    const { bridge } = await setup((socket) => socket.on("data", (chunk) => {
      lines.push(...chunk.toString("utf8").trim().split("\n"));
      const dispatch = lines.map((line) => JSON.parse(line) as { type: string; id?: string }).find((value) => value.type === "tool_dispatch");
      if (dispatch?.id) {
        socket.write(`{\"type\":\"tool_result\",\"id\":\"${dispatch.id}\",`);
        socket.write('"ok":true,"data":{"pid":1}}\n');
      }
    }));
    const result = await bridge.dispatch("launch_app", { app_name: "Safari" }, undefined, randomUUID());
    expect(JSON.parse(lines[0]!).type).toBe("client_hello");
    expect(result).toEqual({ ok: true, data: { pid: 1 }, error: undefined, detail: undefined });
  });

  it("연결 종료 시 진행 중 요청을 즉시 실패시킨다", async () => {
    let peer: net.Socket | undefined;
    const { bridge } = await setup((socket) => { peer = socket; });
    const pending = bridge.dispatch(
      "point_at",
      { frame: { x: 1, y: 1, width: 1, height: 1 } },
      undefined,
      randomUUID(),
    );
    peer!.destroy();
    await expect(pending).resolves.toMatchObject({ ok: false, error: "pet_app_disconnected" });
  });

  it("미연결 호출은 즉시 실패한다", async () => {
    const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-petbridge-log-"));
    const bridge = new PetBridge({ socketPath: socketPath(), logger: new JsonlLogger(logs) });
    await expect(bridge.dispatch("launch_app", {})).resolves.toMatchObject({ error: "pet_app_disconnected" });
  });
});
