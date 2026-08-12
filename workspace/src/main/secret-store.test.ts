import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { SecretStore, type SecretEncryption } from "./secret-store.js";

const encryption: SecretEncryption = {
  isEncryptionAvailable: () => true,
  encryptString: (value) => Buffer.from(`encrypted:${value}`, "utf8"),
  decryptString: (value) => value.toString("utf8").replace(/^encrypted:/, ""),
};

describe("SecretStore", () => {
  it("원문 대신 암호화된 값을 저장하고 복원한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-secret-"));
    const store = new SecretStore(path.join(directory, "secrets.json"), encryption);
    await store.set("claudeApiKey", "secret-value");
    await expect(store.get("claudeApiKey")).resolves.toBe("secret-value");
    await store.delete("claudeApiKey");
    await expect(store.get("claudeApiKey")).resolves.toBeUndefined();
  });

  it("암호화를 사용할 수 없으면 평문 저장을 거부한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-secret-"));
    const store = new SecretStore(path.join(directory, "secrets.json"), { ...encryption, isEncryptionAvailable: () => false });
    await expect(store.set("key", "value")).rejects.toThrow("비밀 저장소");
  });
});
