import { _electron as electron, expect, test } from "@playwright/test";
import path from "node:path";
import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const electronPath = require("electron") as string;

test("EditorGateway로 접속한 Editor View는 재연결(새로고침) 후 열린 탭을 복원한다", async ({ browser }) => {
  const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-gateway-e2e-"));
  await writeFile(path.join(projectPath, "main.ts"), "export const value = 1;\n", "utf8");

  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve("."), "--headless", "--project", projectPath],
    env: { ...process.env, NODE_ENV: "test" },
  });
  try {
    await expect.poll(
      () => application.evaluate(() => typeof (globalThis as { __workspaceTest?: { editorGatewayUrl?: unknown } })
        .__workspaceTest?.editorGatewayUrl),
      { timeout: 15_000 },
    ).toBe("function");
    const url = await application.evaluate(() => (globalThis as { __workspaceTest?: { editorGatewayUrl(id: string): string } })
      .__workspaceTest!.editorGatewayUrl("default"));

    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(url);
    await expect(page.locator(".brand-name")).toHaveText("Workspace", { timeout: 15_000 });

    await page.locator(".tree-row", { hasText: "main.ts" }).click();
    await expect(page.locator(".editor-tab .tab-name", { hasText: "main.ts" })).toBeVisible({ timeout: 10_000 });
    // state:update는 300ms 디바운스로 EditorGateway에 저장된다(App.tsx) -- 새로고침 전에 반영될 시간을 준다.
    await page.waitForTimeout(600);

    await page.reload();
    await expect(page.locator(".brand-name")).toHaveText("Workspace", { timeout: 15_000 });
    await expect(page.locator(".editor-tab .tab-name", { hasText: "main.ts" })).toBeVisible({ timeout: 10_000 });

    await context.close();
  } finally {
    await application.close();
  }
});
