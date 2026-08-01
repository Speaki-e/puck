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
    await expect(window.getByText("Workspace", { exact: true })).toBeVisible();
    await expect(window.getByRole("button", { name: "프로젝트 열기" })).toBeVisible();
    expect(await window.evaluate(() => typeof window.workspace?.selectProject)).toBe("function");
  } finally {
    await application.close();
  }
});
