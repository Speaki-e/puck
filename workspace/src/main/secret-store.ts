import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";

export interface SecretEncryption {
  isEncryptionAvailable(): boolean;
  encryptString(value: string): Buffer;
  decryptString(value: Buffer): string;
}

type StoredSecrets = Record<string, string>;

export class SecretStore {
  constructor(
    private readonly filePath: string,
    private readonly encryption: SecretEncryption,
  ) {}

  get available(): boolean {
    return this.encryption.isEncryptionAvailable();
  }

  async get(key: string): Promise<string | undefined> {
    if (!this.available) return undefined;
    const values = await this.readAll();
    const encoded = values[key];
    if (!encoded) return undefined;
    try {
      return this.encryption.decryptString(Buffer.from(encoded, "base64"));
    } catch {
      return undefined;
    }
  }

  async set(key: string, value: string): Promise<void> {
    if (!this.available) throw new Error("운영체제 비밀 저장소를 사용할 수 없습니다.");
    const values = await this.readAll();
    values[key] = this.encryption.encryptString(value).toString("base64");
    await this.writeAll(values);
  }

  async delete(key: string): Promise<void> {
    const values = await this.readAll();
    delete values[key];
    await this.writeAll(values);
  }

  private async readAll(): Promise<StoredSecrets> {
    try {
      const parsed = JSON.parse(await readFile(this.filePath, "utf8")) as unknown;
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
      return Object.fromEntries(Object.entries(parsed).filter((entry): entry is [string, string] => typeof entry[1] === "string"));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
      throw error;
    }
  }

  private async writeAll(values: StoredSecrets): Promise<void> {
    await mkdir(path.dirname(this.filePath), { recursive: true });
    const temporary = `${this.filePath}.${process.pid}.tmp`;
    await writeFile(temporary, `${JSON.stringify(values, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
    await rename(temporary, this.filePath);
  }
}
