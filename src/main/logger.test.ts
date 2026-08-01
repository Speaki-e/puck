import { access, mkdtemp, readFile, readdir, utimes, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { JsonlLogger } from "./logger.js";

describe("JsonlLogger", () => {
  it("민감한 값과 파일 내용을 마스킹한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-log-"));
    const logger = new JsonlLogger(directory);
    await logger.write("info", "test", { apiKey: "secret", nested: { content: "source" }, safe: "ok" });
    const file = path.join(directory, `${new Date().toISOString().slice(0, 10)}.jsonl`);
    const output = await readFile(file, "utf8");
    expect(output).not.toContain("secret");
    expect(output).not.toContain("source");
    expect(output).toContain("[REDACTED]");
    expect(output).toContain("ok");
  });

  it("최대 크기를 넘으면 로그 파일을 회전한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-log-rotate-"));
    const logger = new JsonlLogger(directory, { maxFileSizeBytes: 180 });
    await logger.write("info", "first", { safe: "a".repeat(80) });
    await logger.write("info", "second", { safe: "b".repeat(80) });
    const files = (await readdir(directory)).filter((file) => file.endsWith(".jsonl"));
    expect(files).toHaveLength(2);
    expect(files.some((file) => /\.1\.jsonl$/.test(file))).toBe(true);
  });

  it("보존 기간이 지난 로그를 다음 기록 시 삭제한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-log-retention-"));
    const oldFile = path.join(directory, "2020-01-01.jsonl");
    await writeFile(oldFile, "{}\n", "utf8");
    await utimes(oldFile, new Date("2020-01-01T00:00:00Z"), new Date("2020-01-01T00:00:00Z"));
    const logger = new JsonlLogger(directory, {
      retentionDays: 7,
      now: () => new Date("2026-08-02T00:00:00Z"),
    });
    await logger.write("info", "cleanup");
    await expect(access(oldFile)).rejects.toThrow();
  });
});
