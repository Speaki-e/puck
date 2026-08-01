import { BrowserWindow, dialog, ipcMain } from "electron";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { FileService } from "./file-service.js";
import { WorkspaceRegistry, type WorkspaceRecord } from "./workspace-registry.js";
import type { SaveFileRequest } from "../shared/file-contract.js";
import { JsonlLogger } from "./logger.js";

export class WorkspaceController {
  private readonly services = new Map<string, FileService>();

  constructor(
    readonly registry: WorkspaceRegistry,
    private readonly logger: JsonlLogger,
  ) {}

  async initialize(projectPath?: string): Promise<void> {
    await this.registry.load();
    if (projectPath) await this.bindDefault(projectPath);
    const current = this.registry.get("default");
    if (current?.realProjectPath) await this.ensureService(current);
  }

  installIpc(): void {
    ipcMain.handle("workspace:select-project", async () => {
      const result = await dialog.showOpenDialog({ properties: ["openDirectory", "createDirectory"] });
      if (result.canceled || !result.filePaths[0]) return undefined;
      return this.bindDefault(result.filePaths[0]);
    });
    ipcMain.handle("workspace:current", () => this.registry.get("default"));
    ipcMain.handle("files:list-tree", async (_event, workspaceId: string) => (await this.service(workspaceId)).listTree());
    ipcMain.handle("files:read", async (_event, workspaceId: string, filePath: string) =>
      (await this.service(workspaceId)).readFile(filePath));
    ipcMain.handle("files:save", async (_event, workspaceId: string, request: SaveFileRequest) => {
      const result = await (await this.service(workspaceId)).saveFile(request);
      await this.logger.write("info", "file_saved", { workspaceId, path: result.path, size: result.size });
      return result;
    });
    ipcMain.handle("agent:run", async (_event, command: string, workspaceId: string) => {
      const requestId = randomUUID();
      this.broadcast("agent:status", `Mock Agent Host 대기: ${command}`);
      await this.logger.write("info", "agent_run_requested", { requestId, workspaceId });
      return { requestId };
    });
    ipcMain.handle("agent:cancel", async () => {
      this.broadcast("agent:status", "취소 요청됨");
      return false;
    });
  }

  async close(): Promise<void> {
    await Promise.all([...this.services.values()].map((service) => service.close()));
    this.services.clear();
    for (const channel of [
      "workspace:select-project",
      "workspace:current",
      "files:list-tree",
      "files:read",
      "files:save",
      "agent:run",
      "agent:cancel",
    ]) ipcMain.removeHandler(channel);
  }

  private async bindDefault(projectPath: string): Promise<WorkspaceRecord> {
    const record = await this.registry.bindProject("default", path.resolve(projectPath));
    await this.services.get("default")?.close();
    this.services.delete("default");
    await this.ensureService(record);
    await this.logger.write("info", "workspace_project_bound", { workspaceId: "default", projectPath: record.realProjectPath });
    return record;
  }

  private async service(workspaceId: string): Promise<FileService> {
    const existing = this.services.get(workspaceId);
    if (existing) return existing;
    const record = this.registry.get(workspaceId);
    if (!record?.realProjectPath) throw new Error("워크스페이스에 프로젝트가 연결되지 않았습니다");
    return this.ensureService(record);
  }

  private async ensureService(record: WorkspaceRecord): Promise<FileService> {
    if (!record.realProjectPath) throw new Error("프로젝트 경로가 없습니다");
    const service = await FileService.create(record.realProjectPath);
    service.on("change", (event) => this.broadcast("files:changed", event));
    await service.startWatching();
    this.services.set(record.id, service);
    return service;
  }

  private broadcast(channel: string, payload: unknown): void {
    for (const window of BrowserWindow.getAllWindows()) {
      if (!window.isDestroyed()) window.webContents.send(channel, payload);
    }
  }
}
