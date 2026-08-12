import { _electron as electron, expect, test } from "@playwright/test";

const packagedExecutable = process.env.WORKSPACE_PACKAGED_EXE;

test("패키지에서 Agent Host와 Claude Agent ACP 진입점을 찾는다", async () => {
  test.setTimeout(60_000);
  test.skip(!packagedExecutable, "WORKSPACE_PACKAGED_EXE가 설정된 패키지 검증에서만 실행합니다");
  const application = await electron.launch({
    executablePath: packagedExecutable!,
    args: ["--headless"],
    env: { ...process.env, NODE_ENV: "test" },
  });
  try {
    await expect.poll(
      () => application.evaluate(async () => {
        try {
          return await (globalThis as any).__workspaceTest?.pingAgentHost();
        } catch {
          return undefined;
        }
      }),
      { timeout: 25_000 },
    ).toBeTruthy();
    const resolved = await application.evaluate(() => (globalThis as any).__workspaceTest.resolveAcpCommand());
    expect(resolved.args[0]).toContain("claude-agent-acp");
    expect(resolved.args[0]).toContain("dist");
  } finally {
    await application.close();
  }
});
