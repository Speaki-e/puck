import { _electron as electron, expect, test } from "@playwright/test";
import path from "node:path";
import net from "node:net";
import os from "node:os";
import { mkdtemp } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const electronPath = require("electron") as string;

test("폴백 셸이 안전한 preload와 함께 열린다", async () => {
  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve(".")],
    env: { ...process.env, NODE_ENV: "test" },
  });
  try {
    const window = await application.firstWindow();
    await window.waitForLoadState("load");
    await expect(window.locator(".brand-name")).toHaveText("Workspace", { timeout: 15_000 });
    await expect(window.locator("header").getByRole("button", { name: "프로젝트 열기" })).toBeVisible();
    expect(await window.evaluate(() => typeof window.workspace?.selectProject)).toBe("function");
    if (process.platform === "win32") {
      await expect(window.getByRole("button", { name: "창 최소화" })).toBeVisible();
      await expect(window.getByRole("button", { name: "창 최대화" })).toBeVisible();
      await expect(window.getByRole("button", { name: "창 닫기" })).toBeVisible();
      expect(await application.evaluate(({ Menu }) => Menu.getApplicationMenu())).toBeNull();
    }
    if (process.env.WORKSPACE_SCREENSHOT) {
      await window.screenshot({ path: process.env.WORKSPACE_SCREENSHOT, animations: "disabled" });
      const appFile = window.locator('[title="src/renderer/App.tsx"]');
      if (await appFile.isVisible()) {
        await appFile.click();
        await window.waitForTimeout(600);
        await expect(window.locator(".squiggly-error")).toHaveCount(0);
        await window.screenshot({ path: process.env.WORKSPACE_SCREENSHOT.replace(/\.png$/i, "-editor.png"), animations: "disabled" });
      }
    }
  } finally {
    await application.close();
  }
});

test("Agent Host가 반복 충돌해도 하나의 프로세스로 복구한다", async () => {
  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve("."), "--headless"],
    env: { ...process.env, NODE_ENV: "test" },
  });
  try {
    await expect.poll(
      () => application.evaluate(async () => {
        try {
          await (globalThis as any).__workspaceTest?.pingAgentHost();
          return true;
        } catch {
          return false;
        }
      }),
      { timeout: 10_000 },
    ).toBe(true);
    let previousPid = await application.evaluate(() => (globalThis as any).__workspaceTest.agentHostPid()) as number;

    for (let attempt = 0; attempt < 3; attempt += 1) {
      await expect(application.evaluate(() => (globalThis as any).__workspaceTest.crashAgentHost())).resolves.toBe(true);
      await expect.poll(
        () => application.evaluate(async () => {
          try {
            const hook = (globalThis as any).__workspaceTest;
            await hook.pingAgentHost();
            return hook.agentHostPid();
          } catch {
            return undefined;
          }
        }).then((pid) => typeof pid === "number" && pid !== previousPid),
        { timeout: 10_000 },
      ).toBe(true);
      const nextPid = await application.evaluate(() => (globalThis as any).__workspaceTest.agentHostPid()) as number;
      expect(typeof nextPid).toBe("number");
      previousPid = nextPid;
    }
  } finally {
    await application.close();
  }
});

test("Agent Host 재시작 상태가 폴백 창 GUI까지 전달되고 완료 후 정상으로 돌아온다", async () => {
  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve(".")],
    env: { ...process.env, NODE_ENV: "test" },
  });
  try {
    const window = await application.firstWindow();
    await window.waitForLoadState("load");
    const statusText = window.locator(".status-text");
    await expect(statusText).toHaveText("준비됨", { timeout: 15_000 });

    const previousPid = await application.evaluate(() => (globalThis as any).__workspaceTest.agentHostPid()) as number;
    await expect(application.evaluate(() => (globalThis as any).__workspaceTest.crashAgentHost())).resolves.toBe(true);

    // 재시작되는 동안 GUI에 "재연결 중"에 해당하는 상태가 보여야 한다(agent-host-controller.ts의
    // "AI 기능을 다시 시작하는 중").
    await expect(statusText).toHaveText("AI 기능을 다시 시작하는 중", { timeout: 10_000 });

    // 재시작이 끝나면(ready) 다시 "준비됨"으로 돌아오고, 새 Agent Host pid로 정상 요청도 된다.
    await expect(statusText).toHaveText("준비됨", { timeout: 10_000 });
    await expect.poll(
      () => application.evaluate(async () => {
        try {
          const hook = (globalThis as any).__workspaceTest;
          await hook.pingAgentHost();
          return hook.agentHostPid();
        } catch {
          return undefined;
        }
      }).then((pid) => typeof pid === "number" && pid !== previousPid),
      { timeout: 10_000 },
    ).toBe(true);
  } finally {
    await application.close();
  }
});

test("Agent Host가 CPU 작업 중이어도 Main 이벤트 루프는 응답한다", async () => {
  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve("."), "--headless"],
    env: { ...process.env, NODE_ENV: "test" },
  });
  try {
    await expect.poll(
      () => application.evaluate(async () => {
        try {
          await (globalThis as any).__workspaceTest?.pingAgentHost();
          return true;
        } catch {
          return false;
        }
      }),
      { timeout: 10_000 },
    ).toBe(true);
    const busy = application.evaluate(() => (globalThis as any).__workspaceTest.busyAgentHost(750));
    const startedAt = Date.now();
    const mainResponse = await application.evaluate(() => "responsive");
    expect(mainResponse).toBe("responsive");
    expect(Date.now() - startedAt).toBeLessThan(300);
    await expect(busy).resolves.toMatchObject({ elapsedMs: expect.any(Number) });
  } finally {
    await application.close();
  }
});

test("PetBridge GUI 입력을 Agent Host로 라우팅하고 상태 이벤트를 반환한다", async () => {
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
  const messages: Array<{ type: string; event?: string }> = [];
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
    peer.write(`${JSON.stringify({ type: "user_input", text: "test", source: "text", workspace_id: "default", session_id: "s1" })}\n`);
    await expect.poll(
      () => messages.some((message) => message.type === "event" && message.event === "agent_thinking"),
      { timeout: 10_000 },
    ).toBe(true);
  } finally {
    await application.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
