import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import type { LogLevel, WorkspaceSettings } from "../shared/settings-contract.js";

export type { WorkspaceSettings } from "../shared/settings-contract.js";

const DEFAULT_SETTINGS: WorkspaceSettings = {
  model: "claude-sonnet-4-5",
  fileSizeLimitBytes: 2 * 1024 * 1024,
  logLevel: "info",
};

const MIN_FILE_SIZE_LIMIT = 64 * 1024;
const LOG_LEVELS = new Set<LogLevel>(["debug", "info", "warn", "error"]);

function sanitize(patch: Partial<WorkspaceSettings>): Partial<WorkspaceSettings> {
  const result: Partial<WorkspaceSettings> = {};
  if (typeof patch.model === "string" && patch.model.trim()) result.model = patch.model.trim();
  if (typeof patch.fileSizeLimitBytes === "number" && Number.isFinite(patch.fileSizeLimitBytes) && patch.fileSizeLimitBytes >= MIN_FILE_SIZE_LIMIT) {
    result.fileSizeLimitBytes = Math.floor(patch.fileSizeLimitBytes);
  }
  if (typeof patch.logLevel === "string" && LOG_LEVELS.has(patch.logLevel)) result.logLevel = patch.logLevel;
  return result;
}

/**
 * 설정 화면(W7)의 모델·파일 크기 상한·로그 수준을 저장한다. API 키는 여기서 다루지 않는다 --
 * 그건 이주한이 만든 SecretStore(safeStorage 암호화)가 그대로 담당한다. 창 크기는
 * WindowStateStore가 자동으로 관리하고, 최근 프로젝트는 WorkspaceRegistry에서 파생하므로
 * 이 저장소는 새로 저장할 필요가 없다.
 */
export class SettingsStore {
  private cached: WorkspaceSettings = { ...DEFAULT_SETTINGS };
  private pending: Promise<void> = Promise.resolve();

  constructor(private readonly filePath: string) {}

  async load(): Promise<WorkspaceSettings> {
    try {
      const raw = JSON.parse(await readFile(this.filePath, "utf8")) as Partial<WorkspaceSettings>;
      this.cached = { ...DEFAULT_SETTINGS, ...sanitize(raw) };
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    return { ...this.cached };
  }

  get current(): WorkspaceSettings {
    return { ...this.cached };
  }

  update(patch: Partial<WorkspaceSettings>): Promise<WorkspaceSettings> {
    this.cached = { ...this.cached, ...sanitize(patch) };
    const snapshot = { ...this.cached };
    this.pending = this.pending.then(async () => {
      await mkdir(path.dirname(this.filePath), { recursive: true });
      const temporary = `${this.filePath}.${process.pid}.${randomUUID()}.tmp`;
      await writeFile(temporary, JSON.stringify(snapshot, null, 2), "utf8");
      await rename(temporary, this.filePath);
    });
    return this.pending.then(() => snapshot);
  }
}
