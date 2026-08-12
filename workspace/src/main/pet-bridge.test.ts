import net from "node:net";
import { mkdtemp, readFile, readdir } from "node:fs/promises";
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

async function readLogLines(directory: string): Promise<Record<string, unknown>[]> {
  const files = (await readdir(directory)).filter((file) => file.endsWith(".jsonl"));
  const contents = await Promise.all(files.map((file) => readFile(path.join(directory, file), "utf8")));
  return contents.join("").trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

// JsonlLogger.write()는 내부 pending 체인을 통해 비동기로 flush되므로, 로그가 파일에 실제로
// 쓰이기까지 약간의 지연이 있을 수 있다 -- 조건이 맞을 때까지 짧게 폴링해 타이밍에 흔들리지 않게 한다.
async function waitForLogEntry(
  directory: string,
  predicate: (entry: Record<string, unknown>) => boolean,
  timeoutMs = 2_000,
): Promise<Record<string, unknown>[]> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const entries = await readLogLines(directory);
    if (entries.some(predicate)) return entries;
    if (Date.now() >= deadline) return entries;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

async function setup(handler: (socket: net.Socket) => void): Promise<{ bridge: PetBridge; address: string; logs: string }> {
  const address = socketPath();
  let resolveAccepted!: () => void;
  const accepted = new Promise<void>((resolve) => { resolveAccepted = resolve; });
  const server = net.createServer((socket) => {
    handler(socket);
    // 테스트가 'data' 리스너를 붙이지 않으면 소켓이 paused 상태로 남아 FIN을 못 받아
    // close 이벤트가 영영 안 나가고 afterEach의 server.close()가 멈춘다 -- 항상 흐르게 한다.
    socket.resume();
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
  return { bridge, address, logs };
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

  it("GUI 입력을 수신 이벤트로 전달하고 Workspace 이벤트를 소켓으로 보낸다", async () => {
    const receivedLines: string[] = [];
    let peer: net.Socket | undefined;
    const { bridge } = await setup((socket) => {
      peer = socket;
      socket.on("data", (chunk) => receivedLines.push(...chunk.toString("utf8").trim().split("\n")));
    });
    const incoming = new Promise<unknown>((resolve) => bridge.once("message", resolve));
    peer!.write(`${JSON.stringify({
      type: "user_input",
      text: "파일을 정리해줘",
      source: "text",
      workspace_id: "w1",
      session_id: "s1",
    })}\n`);

    await expect(incoming).resolves.toMatchObject({ type: "user_input", workspace_id: "w1", session_id: "s1" });
    expect(bridge.sendEvent({
      type: "event",
      workspace_id: "w1",
      session_id: "s1",
      event: "agent_done",
      ok: true,
      summary: "완료",
    })).toBe(true);
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(receivedLines.map((line) => JSON.parse(line))).toContainEqual(expect.objectContaining({
      type: "event",
      event: "agent_done",
      workspace_id: "w1",
      session_id: "s1",
    }));
  });

  it("깨진 JSON을 받아도 크래시 없이 로깅하고 이후 정상 메시지는 계속 처리한다", async () => {
    let peer: net.Socket | undefined;
    const { bridge, logs } = await setup((socket) => { peer = socket; });
    const incoming = new Promise<unknown>((resolve) => bridge.once("message", resolve));

    peer!.write("{ this is not json\n");
    peer!.write(`${JSON.stringify({ type: "user_input", text: "정리해줘", source: "text" })}\n`);

    await expect(incoming).resolves.toMatchObject({ type: "user_input" });
    expect(bridge.state).toBe("connected");
    const entries = await waitForLogEntry(logs, (entry) => entry.kind === "invalid_jsonl");
    expect(entries.some((entry) => entry.kind === "invalid_jsonl")).toBe(true);
  });

  it("알 수 없는 type 메시지를 받아도 크래시 없이 로깅만 하고 넘어간다", async () => {
    let peer: net.Socket | undefined;
    const { bridge, logs } = await setup((socket) => { peer = socket; });
    const incoming = new Promise<unknown>((resolve) => bridge.once("message", resolve));

    peer!.write(`${JSON.stringify({ type: "totally_unknown_type", foo: "bar" })}\n`);
    peer!.write(`${JSON.stringify({ type: "user_input", text: "정리해줘", source: "text" })}\n`);

    await expect(incoming).resolves.toMatchObject({ type: "user_input" });
    expect(bridge.state).toBe("connected");
    const entries = await waitForLogEntry(logs, (entry) => entry.kind === "invalid_protocol_message");
    expect(entries.some((entry) => entry.kind === "invalid_protocol_message")).toBe(true);
  });

  it("필수 필드가 누락된 메시지를 받아도 크래시 없이 로깅만 하고 넘어간다", async () => {
    let peer: net.Socket | undefined;
    const { bridge, logs } = await setup((socket) => { peer = socket; });
    const incoming = new Promise<unknown>((resolve) => bridge.once("message", resolve));

    // user_input에 필수 필드인 text/source가 빠져 있다.
    peer!.write(`${JSON.stringify({ type: "user_input", workspace_id: "w1" })}\n`);
    peer!.write(`${JSON.stringify({ type: "user_input", text: "정리해줘", source: "text" })}\n`);

    await expect(incoming).resolves.toMatchObject({ type: "user_input" });
    expect(bridge.state).toBe("connected");
    const entries = await waitForLogEntry(logs, (entry) => entry.kind === "invalid_protocol_message");
    expect(entries.some((entry) => entry.kind === "invalid_protocol_message")).toBe(true);
  });

  it("대기 중이지 않은 id의 tool_result처럼 알 수 없는 result도 크래시 없이 로깅만 한다", async () => {
    let peer: net.Socket | undefined;
    const { bridge, logs } = await setup((socket) => { peer = socket; });
    const incoming = new Promise<unknown>((resolve) => bridge.once("message", resolve));

    peer!.write(`${JSON.stringify({ type: "tool_result", id: "not-pending", ok: true })}\n`);
    peer!.write(`${JSON.stringify({ type: "user_input", text: "정리해줘", source: "text" })}\n`);

    await expect(incoming).resolves.toMatchObject({ type: "user_input" });
    expect(bridge.state).toBe("connected");
    const entries = await waitForLogEntry(logs, (entry) => entry.kind === "unknown_tool_result");
    expect(entries.some((entry) => entry.kind === "unknown_tool_result")).toBe(true);
  });
});
