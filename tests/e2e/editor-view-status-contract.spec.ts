import { _electron as electron, expect, test } from "@playwright/test";
import path from "node:path";
import net from "node:net";
import os from "node:os";
import { mkdtemp } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const electronPath = require("electron") as string;

/**
 * editor_view_ready/editor_view_unavailable 계약 시험(공통 W2/W4 완료 기준):
 * PetBridge로 나가는 이벤트가 실제로 올바른 workspace_id와, 그 workspace의 EditorGateway URL(같은
 * workspace_id 세그먼트 + 유효한 token)을 담고 있는지 -- 문자열 형태만이 아니라 그 URL이 실제로
 * 200을 반환하는지까지 왕복 검증한다.
 */
test("editor_view_ready/unavailable이 올바른 URL과 workspace_id로 PetBridge에 전달된다", async () => {
  const address = process.platform === "win32"
    ? `\\\\.\\pipe\\workspace-e2e-${randomUUID()}`
    : path.join(os.tmpdir(), `workspace-e2e-${randomUUID()}.sock`);
  const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-editorstatus-e2e-"));
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

    // 1) 시작 시 project_path가 이미 연결된 기본 워크스페이스는 editor_view_ready로 통지된다.
    const ready = await expect.poll(
      () => messages.find((message) => message.type === "editor_view_ready") as
        { workspace_id?: string; url?: string } | undefined,
      { timeout: 10_000 },
    ).not.toBeUndefined().then(() =>
      messages.find((message) => message.type === "editor_view_ready") as { workspace_id: string; url: string },
    );
    expect(ready.workspace_id).toBe("default");
    const readyUrl = new URL(ready.url);
    expect(readyUrl.pathname).toBe("/editor/default/");
    expect(readyUrl.searchParams.get("token")).toBeTruthy();
    const readyResponse = await fetch(ready.url);
    expect(readyResponse.status).toBe(200);

    // 2) project_path 없이 만든 워크스페이스는 editor_view_unavailable(reason=no_project_path)로 통지된다.
    peer.write(`${JSON.stringify({ type: "workspace_create_request", name: "채팅 전용" })}\n`);
    const chatOnly = await expect.poll(
      () => messages.find((message) => message.type === "workspace_create" && message.name === "채팅 전용") as
        { workspace_id?: string } | undefined,
      { timeout: 10_000 },
    ).not.toBeUndefined().then(() =>
      messages.find((message) => message.type === "workspace_create" && message.name === "채팅 전용") as { workspace_id: string },
    );
    await expect.poll(
      () => messages.find((message) =>
        message.type === "editor_view_unavailable" && message.workspace_id === chatOnly.workspace_id) as
        { reason?: string } | undefined,
      { timeout: 10_000 },
    ).toMatchObject({ reason: "no_project_path" });
    expect(messages.some((message) =>
      message.type === "editor_view_ready" && message.workspace_id === chatOnly.workspace_id)).toBe(false);

    // 3) project_path가 있는 새 워크스페이스는 그 workspace_id로 editor_view_ready를 받고,
    //    URL도 그 workspace_id 세그먼트로 실제 서빙된다(다른 워크스페이스 URL과 뒤섞이지 않음).
    const secondProjectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-editorstatus-e2e-2-"));
    peer.write(`${JSON.stringify({ type: "workspace_create_request", name: "두 번째 프로젝트", project_path: secondProjectPath })}\n`);
    const second = await expect.poll(
      () => messages.find((message) => message.type === "workspace_create" && message.name === "두 번째 프로젝트") as
        { workspace_id?: string } | undefined,
      { timeout: 10_000 },
    ).not.toBeUndefined().then(() =>
      messages.find((message) => message.type === "workspace_create" && message.name === "두 번째 프로젝트") as { workspace_id: string },
    );
    const secondReady = await expect.poll(
      () => messages.find((message) =>
        message.type === "editor_view_ready" && message.workspace_id === second.workspace_id) as
        { url?: string } | undefined,
      { timeout: 10_000 },
    ).not.toBeUndefined().then(() =>
      messages.find((message) =>
        message.type === "editor_view_ready" && message.workspace_id === second.workspace_id) as { url: string },
    );
    expect(new URL(secondReady.url).pathname).toBe(`/editor/${second.workspace_id}/`);
    expect(secondReady.url).not.toBe(ready.url);
    const secondResponse = await fetch(secondReady.url);
    expect(secondResponse.status).toBe(200);
  } finally {
    await application.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
