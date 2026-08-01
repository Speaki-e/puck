import { _electron as electron, expect, test } from "@playwright/test";
import path from "node:path";
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
      () => application.evaluate(() => (globalThis as any).__workspaceTest?.agentHostPid()),
      { timeout: 10_000 },
    ).not.toBeUndefined();
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
        }),
        { timeout: 10_000 },
      ).not.toBe(previousPid);
      const nextPid = await application.evaluate(() => (globalThis as any).__workspaceTest.agentHostPid()) as number;
      expect(typeof nextPid).toBe("number");
      previousPid = nextPid;
    }
  } finally {
    await application.close();
  }
});
