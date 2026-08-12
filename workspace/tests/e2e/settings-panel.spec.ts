import { _electron as electron, expect, test } from "@playwright/test";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const electronPath = require("electron") as string;

test("설정 화면에서 로그 수준·모델을 바꾸고 API 키를 안전하게 저장/삭제한다", async () => {
  const application = await electron.launch({
    executablePath: electronPath,
    args: [path.resolve(".")],
    env: { ...process.env, NODE_ENV: "test" },
  });
  try {
    const window = await application.firstWindow();
    await window.waitForLoadState("load");
    await expect(window.locator(".brand-name")).toHaveText("Workspace", { timeout: 15_000 });

    await window.getByRole("button", { name: "설정" }).click();
    const panel = window.locator(".settings-panel");
    await expect(panel).toBeVisible({ timeout: 10_000 });

    await window.getByLabel("로그 수준").selectOption("debug");
    await window.getByLabel("모델").fill("claude-opus-5");
    await window.getByLabel("모델").blur();

    // API 키 저장 -- 값 자체가 렌더러/DOM에 남지 않는지 확인한다(hasApiKey 플래그만 반영).
    await window.getByLabel("Claude API 키").fill("sk-ant-test-secret-value");
    await panel.getByRole("button", { name: "저장" }).click();
    await expect(panel.locator(".settings-hint", { hasText: "설정돼 있습니다" })).toBeVisible({ timeout: 10_000 });
    expect(await panel.innerHTML()).not.toContain("sk-ant-test-secret-value");

    await panel.getByRole("button", { name: "삭제" }).click();
    await expect(panel.locator(".settings-hint", { hasText: "설정되지 않았습니다" })).toBeVisible({ timeout: 10_000 });

    // 닫았다가 다시 열어도(재조회) 로그 수준·모델이 유지된다.
    await window.getByLabel("설정 닫기").click();
    await expect(panel).toHaveCount(0);
    await window.getByRole("button", { name: "설정" }).click();
    await expect(window.getByLabel("로그 수준")).toHaveValue("debug", { timeout: 10_000 });
    await expect(window.getByLabel("모델")).toHaveValue("claude-opus-5");
  } finally {
    await application.close();
  }
});
