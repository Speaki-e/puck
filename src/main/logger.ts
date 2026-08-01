import { appendFile, mkdir, readdir, stat, unlink } from "node:fs/promises";
import path from "node:path";

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogEntry {
  ts: string;
  src: "workspace";
  level: LogLevel;
  kind: string;
  [key: string]: unknown;
}

const REDACTED_KEYS = new Set(["apiKey", "api_key", "authorization", "content", "token"]);

export interface JsonlLoggerOptions {
  maxFileSizeBytes?: number;
  retentionDays?: number;
  maxFiles?: number;
  now?: () => Date;
}

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, REDACTED_KEYS.has(key) ? "[REDACTED]" : redact(item)]),
  );
}

export class JsonlLogger {
  private pending: Promise<void> = Promise.resolve();
  private lastCleanupDay?: string;

  constructor(
    private readonly logDirectory: string,
    private readonly options: JsonlLoggerOptions = {},
  ) {}

  write(level: LogLevel, kind: string, data: Record<string, unknown> = {}): Promise<void> {
    const operation = this.pending.then(() => this.writeEntry(level, kind, data));
    this.pending = operation.catch(() => undefined);
    return operation;
  }

  private async writeEntry(level: LogLevel, kind: string, data: Record<string, unknown>): Promise<void> {
    await mkdir(this.logDirectory, { recursive: true });
    const now = this.options.now?.() ?? new Date();
    const day = now.toISOString().slice(0, 10);
    if (this.lastCleanupDay !== day) {
      await this.cleanup(now);
      this.lastCleanupDay = day;
    }
    const entry: LogEntry = {
      ts: now.toISOString(),
      src: "workspace",
      level,
      kind,
      ...(redact(data) as Record<string, unknown>),
    };
    const line = `${JSON.stringify(entry)}\n`;
    const file = await this.targetFile(day, Buffer.byteLength(line));
    await appendFile(file, line, "utf8");
  }

  private async targetFile(day: string, incomingBytes: number): Promise<string> {
    const maxBytes = this.options.maxFileSizeBytes ?? 5 * 1024 * 1024;
    for (let segment = 0; ; segment += 1) {
      const name = segment === 0 ? `${day}.jsonl` : `${day}.${segment}.jsonl`;
      const file = path.join(this.logDirectory, name);
      try {
        const info = await stat(file);
        if (info.size === 0 || info.size + incomingBytes <= maxBytes) return file;
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") return file;
        throw error;
      }
    }
  }

  private async cleanup(now: Date): Promise<void> {
    const retentionMs = (this.options.retentionDays ?? 14) * 24 * 60 * 60 * 1_000;
    const maxFiles = this.options.maxFiles ?? 30;
    const files = (await readdir(this.logDirectory))
      .filter((file) => /^\d{4}-\d{2}-\d{2}(?:\.\d+)?\.jsonl$/.test(file));
    const entries = await Promise.all(files.map(async (file) => ({
      file,
      mtimeMs: (await stat(path.join(this.logDirectory, file))).mtimeMs,
    })));
    const retained = entries.filter((entry) => now.getTime() - entry.mtimeMs <= retentionMs)
      .sort((left, right) => right.mtimeMs - left.mtimeMs);
    const removals = [
      ...entries.filter((entry) => now.getTime() - entry.mtimeMs > retentionMs),
      ...retained.slice(maxFiles),
    ];
    await Promise.all(removals.map((entry) => unlink(path.join(this.logDirectory, entry.file))));
  }
}
