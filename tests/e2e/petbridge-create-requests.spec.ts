import { _electron as electron, expect, test } from "@playwright/test";
import path from "node:path";
import net from "node:net";
import os from "node:os";
import { mkdtemp } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const electronPath = require("electron") as string;

test("workspace_create_request/session_create_request에 확정 이벤트로 응답한다", async () => {
  const address = process.platform === "win32"
    ? `\\\\.\\pipe\\workspace-e2e-${randomUUID()}`
    : path.join(os.tmpdir(), `workspace-e2e-${randomUUID()}.sock`);
  const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-bridge-e2e-"));
  let resolvePeer!: (socket: net.Socket) => void;
  const peerConnected = new Promise<net.Socket>((resolve) => { resolvePeer = resolve; });
  const server = net.createServer(resolvePeer);
  await new Promise<void>((resolve, reject) => server.listen(address, resolve).once("error", reject));
  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve("."), "--headless", "--project", projectPath, "--bridge-socket", address],
    env: { ...process.env, NODE_ENV: "test" },
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

    const newProjectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-bridge-e2e-2-"));
    peer.write(`${JSON.stringify({ type: "workspace_create_request", name: "두 번째 워크스페이스", project_path: newProjectPath })}\n`);
    await expect.poll(
      () => messages.find((message) => message.type === "workspace_create") as { workspace_id?: string; name?: string } | undefined,
      { timeout: 10_000 },
    ).toMatchObject({ name: "두 번째 워크스페이스" });
    const workspaceCreate = messages.find((message) => message.type === "workspace_create") as { workspace_id: string };

    peer.write(`${JSON.stringify({ type: "session_create_request", workspace_id: workspaceCreate.workspace_id, title: "새 대화" })}\n`);
    await expect.poll(
      () => messages.some((message) => message.type === "session_create" && message.workspace_id === workspaceCreate.workspace_id && message.origin === "user"),
      { timeout: 10_000 },
    ).toBe(true);
  } finally {
    await application.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
