import { _electron as electron, expect, test } from "@playwright/test";
import path from "node:path";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const electronPath = require("electron") as string;

test("파일 충돌 시 diff를 확인하고 '내 내용 유지'로 저장해도 손상 없이 반영된다", async ({ browser }) => {
  const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-conflict-e2e-"));
  const filePath = path.join(projectPath, "main.ts");
  await writeFile(filePath, "export const value = 1;\n", "utf8");

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

    // 내 편집: 에디터에 포커스해 전체 선택 후 새 내용을 입력한다.
    await page.locator(".monaco-editor").first().click();
    await page.keyboard.press("Control+A");
    await page.keyboard.type("export const value = 999; // mine\n");
    await expect(page.locator(".dirty-dot")).toBeVisible({ timeout: 5_000 });

    // 디스크에서 파일이 바뀐 상황을 재현한다.
    await writeFile(filePath, "export const value = 42; // external\n", "utf8");
    await expect(page.locator(".conflict-banner")).toBeVisible({ timeout: 10_000 });

    await page.getByRole("button", { name: "diff 비교" }).click();
    await expect(page.locator(".monaco-diff-editor")).toBeVisible({ timeout: 10_000 });
    await page.getByRole("button", { name: "diff 닫기" }).click();
    await expect(page.locator(".monaco-diff-editor")).toHaveCount(0);

    await page.getByRole("button", { name: "내 내용 유지" }).click();
    await expect(page.locator(".conflict-banner")).toHaveCount(0);
    await page.keyboard.press("Control+S");
    await expect(page.locator(".dirty-dot")).toHaveCount(0, { timeout: 10_000 });

    const savedContent = await readFile(filePath, "utf8");
    expect(savedContent).toContain("999");
    expect(savedContent).not.toContain("42");

    await context.close();
  } finally {
    await application.close();
  }
});
