import { appendFile, mkdir, readdir, stat, unlink } from "node:fs/promises";
import path from "node:path";
import type { LogLevel } from "../shared/settings-contract.js";

/**
 * 로그에 프로젝트/첨부/소켓의 절대경로를 그대로 남기면 사용자 홈 디렉터리와 OS 사용자명이
 * 새어나간다(공통 W7, 로그 정책 리뷰). REDACTED_KEYS는 키 이름 기준이라 `projectPath`처럼
 * 디버깅에 값 자체가 필요한 필드는 못 가리므로, 마지막 세그먼트만 남겨 어떤 프로젝트/파일인지는
 * 계속 구분하면서 상위 경로(홈 디렉터리 등)는 감춘다.
 */
export function basenameForLog(absolutePath: string): string;
export function basenameForLog(absolutePath: string | undefined): string | undefined;
export function basenameForLog(absolutePath: string | undefined): string | undefined {
  if (absolutePath === undefined) return undefined;
  return path.basename(absolutePath) || absolutePath;
}

export type { LogLevel } from "../shared/settings-contract.js";

export interface LogEntry {
  ts: string;
  src: "workspace";
  level: LogLevel;
  kind: string;
  [key: string]: unknown;
}

const REDACTED_KEYS = new Set(["apiKey", "api_key", "authorization", "content", "token"]);
const LEVEL_ORDER: Record<LogLevel, number> = { debug: 0, info: 1, warn: 2, error: 3 };

export interface JsonlLoggerOptions {
  maxFileSizeBytes?: number;
  retentionDays?: number;
  maxFiles?: number;
  now?: () => Date;
  /** 설정 화면의 "로그 수준"(W7, 김민영) -- 기본값 debug는 기존 동작(전부 기록)과 동일하다. */
  minLevel?: LogLevel;
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
  private minLevel: LogLevel;

  constructor(
    private readonly logDirectory: string,
    private readonly options: JsonlLoggerOptions = {},
  ) {
    this.minLevel = options.minLevel ?? "debug";
  }

  /** 설정 화면에서 로그 수준을 바꾸면 재시작 없이 반영하기 위한 진입점. */
  setMinLevel(level: LogLevel): void {
    this.minLevel = level;
  }

  write(level: LogLevel, kind: string, data: Record<string, unknown> = {}): Promise<void> {
    if (LEVEL_ORDER[level] < LEVEL_ORDER[this.minLevel]) return Promise.resolve();
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
