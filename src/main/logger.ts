import { appendFile, mkdir } from "node:fs/promises";
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

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, REDACTED_KEYS.has(key) ? "[REDACTED]" : redact(item)]),
  );
}

export class JsonlLogger {
  constructor(private readonly logDirectory: string) {}

  async write(level: LogLevel, kind: string, data: Record<string, unknown> = {}): Promise<void> {
    await mkdir(this.logDirectory, { recursive: true });
    const file = path.join(this.logDirectory, `${new Date().toISOString().slice(0, 10)}.jsonl`);
    const entry: LogEntry = {
      ts: new Date().toISOString(),
      src: "workspace",
      level,
      kind,
      ...(redact(data) as Record<string, unknown>),
    };
    await appendFile(file, `${JSON.stringify(entry)}\n`, "utf8");
  }
}
