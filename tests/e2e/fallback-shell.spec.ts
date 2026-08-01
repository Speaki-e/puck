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
