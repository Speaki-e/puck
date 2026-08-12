import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

export interface WindowState {
  x: number;
  y: number;
  width: number;
  height: number;
  maximized: boolean;
}

export interface WorkArea {
  x: number;
  y: number;
  width: number;
  height: number;
}

const DEFAULT_STATE: WindowState = { x: 80, y: 60, width: 1280, height: 800, maximized: false };

function validState(value: unknown): value is WindowState {
  if (!value || typeof value !== "object") return false;
  const state = value as Partial<WindowState>;
  return [state.x, state.y, state.width, state.height].every(Number.isFinite)
    && state.width! >= 880 && state.height! >= 560 && typeof state.maximized === "boolean";
}

function intersectionArea(state: WindowState, area: WorkArea): number {
  const width = Math.max(0, Math.min(state.x + state.width, area.x + area.width) - Math.max(state.x, area.x));
  const height = Math.max(0, Math.min(state.y + state.height, area.y + area.height) - Math.max(state.y, area.y));
  return width * height;
}

export function normalizeWindowState(state: WindowState | undefined, workAreas: WorkArea[]): WindowState {
  const candidate = state ?? DEFAULT_STATE;
  const target = workAreas.reduce<WorkArea | undefined>((best, area) => (
    !best || intersectionArea(candidate, area) > intersectionArea(candidate, best) ? area : best
  ), undefined) ?? { x: 0, y: 0, width: 1280, height: 800 };
  const width = Math.min(Math.max(candidate.width, 880), target.width);
  const height = Math.min(Math.max(candidate.height, 560), target.height);
  if (intersectionArea(candidate, target) >= 64 * 64) return { ...candidate, width, height };
  return {
    x: target.x + Math.round((target.width - width) / 2),
    y: target.y + Math.round((target.height - height) / 2),
    width,
    height,
    maximized: candidate.maximized,
  };
}

export class WindowStateStore {
  private pending: Promise<void> = Promise.resolve();

  constructor(private readonly storageFile: string) {}

  async load(): Promise<WindowState | undefined> {
    try {
      const value: unknown = JSON.parse(await readFile(this.storageFile, "utf8"));
      return validState(value) ? value : undefined;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT" && !(error instanceof SyntaxError)) throw error;
      return undefined;
    }
  }

  save(state: WindowState): Promise<void> {
    this.pending = this.pending.then(async () => {
      await mkdir(path.dirname(this.storageFile), { recursive: true });
      const temporary = `${this.storageFile}.${process.pid}.${randomUUID()}.tmp`;
      await writeFile(temporary, JSON.stringify(state, null, 2), "utf8");
      await rename(temporary, this.storageFile);
    });
    return this.pending;
  }

  flush(): Promise<void> {
    return this.pending;
  }
}
