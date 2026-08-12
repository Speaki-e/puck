import { mkdir, readFile, realpath, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

export interface WorkspaceRecord {
  id: string;
  name: string;
  projectPath?: string;
  realProjectPath?: string;
  createdAt: number;
  updatedAt: number;
}

interface PersistedRegistry {
  version: 1;
  workspaces: WorkspaceRecord[];
}

export class WorkspaceRegistry {
  private readonly records = new Map<string, WorkspaceRecord>();

  constructor(private readonly storageFile: string) {
    this.ensureDefault();
  }

  async load(): Promise<void> {
    try {
      const parsed = JSON.parse(await readFile(this.storageFile, "utf8")) as PersistedRegistry;
      if (parsed.version !== 1 || !Array.isArray(parsed.workspaces)) return;
      this.records.clear();
      for (const record of parsed.workspaces) this.records.set(record.id, record);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    this.ensureDefault();
  }

  list(): WorkspaceRecord[] {
    return [...this.records.values()].map((record) => ({ ...record }));
  }

  get(id: string): WorkspaceRecord | undefined {
    const record = this.records.get(id);
    return record ? { ...record } : undefined;
  }

  async create(name: string, projectPath?: string, id: string = randomUUID()): Promise<WorkspaceRecord> {
    if (this.records.has(id)) throw new Error(`workspace already exists: ${id}`);
    const now = Date.now();
    const normalized = projectPath ? path.resolve(projectPath) : undefined;
    const record: WorkspaceRecord = {
      id,
      name: name.trim() || "Workspace",
      projectPath: normalized,
      realProjectPath: normalized ? await realpath(normalized) : undefined,
      createdAt: now,
      updatedAt: now,
    };
    this.records.set(id, record);
    await this.persist();
    return { ...record };
  }

  async bindProject(id: string, projectPath: string): Promise<WorkspaceRecord> {
    const current = this.records.get(id);
    if (!current) throw new Error(`workspace not found: ${id}`);
    const normalized = path.resolve(projectPath);
    const record = {
      ...current,
      projectPath: normalized,
      realProjectPath: await realpath(normalized),
      updatedAt: Date.now(),
    };
    this.records.set(id, record);
    await this.persist();
    return { ...record };
  }

  async remove(id: string): Promise<boolean> {
    if (id === "default") return false;
    const removed = this.records.delete(id);
    if (removed) await this.persist();
    return removed;
  }

  private ensureDefault(): void {
    if (this.records.has("default")) return;
    const now = Date.now();
    this.records.set("default", {
      id: "default",
      name: "기본 워크스페이스",
      createdAt: now,
      updatedAt: now,
    });
  }

  private async persist(): Promise<void> {
    await mkdir(path.dirname(this.storageFile), { recursive: true });
    const temporary = `${this.storageFile}.${process.pid}.${randomUUID()}.tmp`;
    const data: PersistedRegistry = { version: 1, workspaces: this.list() };
    await writeFile(temporary, JSON.stringify(data, null, 2), "utf8");
    await rename(temporary, this.storageFile);
  }
}
