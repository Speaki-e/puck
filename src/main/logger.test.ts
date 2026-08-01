import { mkdtemp, readFile } from "node:fs/promises";
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
});
