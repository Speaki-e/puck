import { _electron as electron, expect, test } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { mkdtemp } from "node:fs/promises";
import { createServer } from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const electronPath = require("electron") as string;

function sendEvent(response: import("node:http").ServerResponse, name: string, data: unknown): void {
  response.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
}

test("PetBridge 입력이 로컬 Anthropic 호환 endpoint를 거쳐 스트리밍으로 돌아온다", async () => {
  const anthropic = createServer((request, response) => {
    if (request.method !== "POST" || request.url !== "/v1/messages") {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, { "content-type": "text/event-stream" });
    sendEvent(response, "message_start", {
      type: "message_start",
      message: {
        id: "msg_e2e", type: "message", role: "assistant", model: "local-test", content: [],
        stop_reason: null, stop_sequence: null, usage: { input_tokens: 1, output_tokens: 0 },
      },
    });
    sendEvent(response, "content_block_start", {
      type: "content_block_start", index: 0, content_block: { type: "text", text: "" },
    });
    sendEvent(response, "content_block_delta", {
      type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "local endpoint response" },
    });
    sendEvent(response, "content_block_stop", { type: "content_block_stop", index: 0 });
    sendEvent(response, "message_delta", {
      type: "message_delta", delta: { stop_reason: "end_turn", stop_sequence: null }, usage: { output_tokens: 3 },
    });
    sendEvent(response, "message_stop", { type: "message_stop" });
    response.end();
  });
  await new Promise<void>((resolve, reject) => anthropic.listen(0, "127.0.0.1", resolve).once("error", reject));
  const endpoint = `http://127.0.0.1:${(anthropic.address() as net.AddressInfo).port}`;

  const address = process.platform === "win32"
    ? `\\\\.\\pipe\\workspace-e2e-${randomUUID()}`
    : path.join(os.tmpdir(), `workspace-e2e-${randomUUID()}.sock`);
  const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-local-anthropic-e2e-"));
  let resolvePeer!: (socket: net.Socket) => void;
  const peerConnected = new Promise<net.Socket>((resolve) => { resolvePeer = resolve; });
  const bridge = net.createServer(resolvePeer);
  await new Promise<void>((resolve, reject) => bridge.listen(address, resolve).once("error", reject));

  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve("."), "--headless", "--project", projectPath, "--bridge-socket", address],
    env: {
      ...process.env,
      NODE_ENV: "development",
      ANTHROPIC_API_KEY: "local-test-key",
      ANTHROPIC_BASE_URL: endpoint,
    },
  });
  const messages: Array<Record<string, unknown>> = [];
  try {
    const peer = await peerConnected;
    let buffer = "";
    peer.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) if (line) messages.push(JSON.parse(line));
    });
    await expect.poll(() => messages.some((message) => message.type === "client_hello"), { timeout: 10_000 }).toBe(true);

    peer.write(`${JSON.stringify({
      type: "user_input", text: "local endpoint check", source: "text", workspace_id: "default", session_id: "local-e2e",
    })}\n`);

    await expect.poll(
      () => messages.some((message) => message.event === "text_chunk" && message.text === "local endpoint response"),
      { timeout: 10_000 },
    ).toBe(true);
    await expect.poll(
      () => messages.some((message) => message.event === "agent_done" && message.ok === true),
      { timeout: 10_000 },
    ).toBe(true);
  } finally {
    await application.close();
    await new Promise<void>((resolve) => bridge.close(() => resolve()));
    await new Promise<void>((resolve) => anthropic.close(() => resolve()));
  }
});
