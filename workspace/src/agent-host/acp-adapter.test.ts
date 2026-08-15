import { access, mkdtemp, readFile } from "node:fs/promises";
import { EventEmitter } from "node:events";
import os from "node:os";
import path from "node:path";
import { Readable, Writable } from "node:stream";
import { describe, expect, it, vi } from "vitest";
import { AcpAdapter, type AcpAdapterOptions } from "./acp-adapter.js";
import type { ChildProcessWithoutNullStreams } from "node:child_process";

/**
 * A stub child process that "spawns" successfully but exits immediately
 * (asynchronously), so `AcpAdapter.run` resolves quickly with a failure
 * result instead of hanging while waiting for a real ACP handshake. This
 * lets the tests below assert on the spawned command/args/env without
 * needing a working mock ACP agent on stdout/stdin.
 */
function makeStubChild(): ChildProcessWithoutNullStreams {
  const stdin = new Writable({ write: (_chunk, _enc, cb) => cb() });
  const stdout = new Readable({ read: () => undefined });
  const stderr = new Readable({ read: () => undefined });
  stdout.push(null);
  stderr.push(null);
  const child = new EventEmitter() as unknown as ChildProcessWithoutNullStreams;
  Object.assign(child, { stdin, stdout, stderr, killed: false, kill: () => true });
  queueMicrotask(() => child.emit("exit", 1, null));
  return child;
}

describe("AcpAdapter", () => {
  it("공식 SDK로 Mock ACP Agent를 실행하고 변경 파일을 수집한다", async () => {
    const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-"));
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const onUpdate = vi.fn();
    const adapter = new AcpAdapter({ command: process.execPath, args: [fixture], onUpdate });
    const result = await adapter.run({
      requestId: "r1",
      workspaceId: "w1",
      task: "파일을 수정해줘",
      projectPath,
      signal: new AbortController().signal,
    });

    expect(result).toMatchObject({ ok: true, summary: "Mock ACP 작업 완료" });
    expect(result.changedFiles).toContain("mock-change.txt");
    await expect(readFile(path.join(projectPath, "mock-change.txt"), "utf8")).resolves.toBe("changed by mock acp\n");
    expect(onUpdate).toHaveBeenCalled();
  });

  it("이미 취소된 요청은 프로세스를 실행하지 않는다", async () => {
    const spawnProcess = vi.fn();
    const controller = new AbortController();
    controller.abort();
    const adapter = new AcpAdapter({ spawnProcess: spawnProcess as never });
    const result = await adapter.run({
      requestId: "r2",
      workspaceId: "w1",
      task: "실행하지 마",
      projectPath: process.cwd(),
      signal: controller.signal,
    });
    expect(result).toMatchObject({ ok: false, error: "cancelled" });
    expect(spawnProcess).not.toHaveBeenCalled();
  });

  it("ACP 프로세스가 비정상 종료된 뒤 다음 작업에서 새 프로세스로 복구한다", async () => {
    const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-crash-"));
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const adapter = new AcpAdapter({ command: process.execPath, args: [fixture] });

    const crashed = await adapter.run({
      requestId: "crash",
      workspaceId: "w1",
      task: "CRASH",
      projectPath,
      signal: new AbortController().signal,
    });
    expect(crashed).toMatchObject({ ok: false, error: "acp_error" });
    expect(crashed.detail).toContain("intentional mock ACP crash");

    const recovered = await adapter.run({
      requestId: "recover",
      workspaceId: "w1",
      task: "recover",
      projectPath,
      signal: new AbortController().signal,
    });
    expect(recovered.ok).toBe(true);
    expect(recovered.changedFiles).toContain("mock-change.txt");
  });

  it("실행 중 취소하면 쓰기 전에 멈춰 부분 파일을 남기지 않는다", async () => {
    const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-cancel-"));
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const adapter = new AcpAdapter({ command: process.execPath, args: [fixture] });
    const controller = new AbortController();
    const run = adapter.run({
      requestId: "cancel",
      workspaceId: "w1",
      task: "WAIT",
      projectPath,
      signal: controller.signal,
    });
    setTimeout(() => controller.abort(), 150);

    await expect(run).resolves.toMatchObject({ ok: false, error: "cancelled", changedFiles: [] });
    await expect(access(path.join(projectPath, "mock-change.txt"))).rejects.toThrow();
  });

  async function runWithStub(options: AcpAdapterOptions) {
    const spawnProcess = vi.fn((..._args: unknown[]) => makeStubChild());
    const adapter = new AcpAdapter({ ...options, spawnProcess: spawnProcess as never });
    await adapter.run({
      requestId: "stub",
      workspaceId: "w1",
      task: "noop",
      projectPath: process.cwd(),
      signal: new AbortController().signal,
    });
    expect(spawnProcess).toHaveBeenCalledTimes(1);
    const [command, args, spawnOptions] = spawnProcess.mock.calls[0]!;
    return { command: command as string, args: args as string[], env: (spawnOptions as { env: NodeJS.ProcessEnv }).env };
  }

  function withEnv(overrides: Record<string, string | undefined>, fn: () => Promise<void>) {
    const originals: Record<string, string | undefined> = {};
    for (const key of Object.keys(overrides)) originals[key] = process.env[key];
    for (const [key, value] of Object.entries(overrides)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    return fn().finally(() => {
      for (const [key, value] of Object.entries(originals)) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
    });
  }

  it("agentKind 기본값(claude)은 claude-agent-acp 경로로 스폰한다", async () => {
    const { args } = await runWithStub({});
    expect(args.some((arg) => arg.includes("claude-agent-acp"))).toBe(true);
  });

  it("agentKind이 codex이면 codex-acp 경로로 스폰한다", async () => {
    const { args } = await runWithStub({ agentKind: "codex" });
    expect(args.some((arg) => arg.includes("codex-acp"))).toBe(true);
  });

  it("codex 선택 시 OPENAI_API_KEY를 전달하고 ANTHROPIC_API_KEY는 전달하지 않는다", async () => {
    await withEnv({ ANTHROPIC_API_KEY: undefined, OPENAI_API_KEY: "openai-test-key", CODEX_API_KEY: undefined }, async () => {
      const { env } = await runWithStub({ agentKind: "codex" });
      expect(env.OPENAI_API_KEY).toBe("openai-test-key");
      expect(env.ANTHROPIC_API_KEY).toBeUndefined();
    });
  });

  it("claude(기본값) 선택 시 ANTHROPIC_API_KEY를 전달하고 OPENAI_API_KEY/CODEX_API_KEY는 전달하지 않는다", async () => {
    await withEnv({ ANTHROPIC_API_KEY: "anthropic-test-key", OPENAI_API_KEY: undefined, CODEX_API_KEY: undefined }, async () => {
      const { env } = await runWithStub({});
      expect(env.ANTHROPIC_API_KEY).toBe("anthropic-test-key");
      expect(env.OPENAI_API_KEY).toBeUndefined();
      expect(env.CODEX_API_KEY).toBeUndefined();
    });
  });
});
