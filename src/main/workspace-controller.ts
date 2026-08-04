import { BrowserWindow, dialog, ipcMain } from "electron";
import path from "node:path";
import { EventEmitter } from "node:events";
import { FileService } from "./file-service.js";
import { WorkspaceRegistry, type WorkspaceRecord } from "./workspace-registry.js";
import type { SaveFileRequest } from "../shared/file-contract.js";
import { basenameForLog, JsonlLogger } from "./logger.js";

export class WorkspaceController extends EventEmitter {
  private readonly services = new Map<string, FileService>();
  private runAgent: (command: string, workspace: WorkspaceRecord) => Promise<{ requestId: string }> = async (command) => ({ requestId: `mock-${command}` });
  private cancelAgent: () => Promise<boolean> = async () => false;

  constructor(
    readonly registry: WorkspaceRegistry,
    private readonly logger: JsonlLogger,
    /** 설정 화면(W7)의 파일 크기 상한을 새로 여는 FileService에 반영하기 위한 훅. */
    private readonly getEditableSizeLimit?: () => number,
  ) {
    super();
  }

  async initialize(projectPath?: string): Promise<void> {
    await this.registry.load();
    if (projectPath) await this.bindDefault(projectPath);
    const current = this.registry.get("default");
    if (current?.realProjectPath) await this.ensureService(current);
  }

  setAgentCommands(commands: {
    run(command: string, workspace: WorkspaceRecord): Promise<{ requestId: string }>;
    cancel(): Promise<boolean>;
  }): void {
    this.runAgent = commands.run;
    this.cancelAgent = commands.cancel;
  }

  async runCommand(command: string, workspaceId: string): Promise<{ requestId: string }> {
    const workspace = this.registry.get(workspaceId);
    if (!workspace?.realProjectPath) throw new Error("프로젝트가 연결되지 않았습니다");
    const result = await this.runAgent(command, workspace);
    await this.logger.write("info", "agent_run_requested", { requestId: result.requestId, workspaceId });
    return result;
  }

  async cancelCommand(): Promise<boolean> {
    this.broadcast("agent:status", "취소 요청 중");
    return this.cancelAgent();
  }

  /** EditorGateway(김민영 W2)가 같은 워크스페이스의 FileService 인스턴스를 재사용하기 위한 접점. */
  getFileService(workspaceId: string): Promise<FileService> {
    return this.service(workspaceId);
  }

  installIpc(): void {
    ipcMain.handle("workspace:select-project", async () => {
      const result = await dialog.showOpenDialog({ properties: ["openDirectory", "createDirectory"] });
      if (result.canceled || !result.filePaths[0]) return undefined;
      return this.bindDefault(result.filePaths[0]);
    });
    ipcMain.handle("workspace:current", () => this.registry.get("default"));
    // 설정 화면의 "최근 프로젝트" 목록에서 다이얼로그 없이 바로 전환하기 위한 진입점.
    ipcMain.handle("workspace:bind-project", (_event, projectPath: string) => this.bindDefault(projectPath));
    ipcMain.handle("files:list-tree", async (_event, workspaceId: string) => (await this.service(workspaceId)).listTree());
    ipcMain.handle("files:read", async (_event, workspaceId: string, filePath: string) =>
      (await this.service(workspaceId)).readFile(filePath));
    ipcMain.handle("files:preview-image", async (_event, workspaceId: string, filePath: string) =>
      (await this.service(workspaceId)).readImagePreview(filePath));
    ipcMain.handle("files:save", async (_event, workspaceId: string, request: SaveFileRequest) => {
      const result = await (await this.service(workspaceId)).saveFile(request);
      await this.logger.write("info", "file_saved", { workspaceId, path: result.path, size: result.size });
      return result;
    });
    ipcMain.handle("agent:run", async (_event, command: string, workspaceId: string) => {
      const workspace = this.registry.get(workspaceId);
      if (!workspace?.realProjectPath) throw new Error("프로젝트가 연결되지 않았습니다");
      const result = await this.runAgent(command, workspace);
      await this.logger.write("info", "agent_run_requested", { requestId: result.requestId, workspaceId });
      return result;
    });
    ipcMain.handle("agent:cancel", async () => {
      this.broadcast("agent:status", "취소 요청됨");
      return this.cancelAgent();
    });
    ipcMain.handle("window:control", (event, action: "minimize" | "maximize" | "close") => {
      const window = BrowserWindow.fromWebContents(event.sender);
      if (!window) return false;
      if (action === "minimize") window.minimize();
      else if (action === "maximize") window.isMaximized() ? window.unmaximize() : window.maximize();
      else if (action === "close") window.close();
      return true;
    });
  }

  async close(): Promise<void> {
    await Promise.all([...this.services.values()].map((service) => service.close()));
    this.services.clear();
    for (const channel of [
      "workspace:select-project",
      "workspace:current",
      "workspace:bind-project",
      "files:list-tree",
      "files:read",
      "files:preview-image",
      "files:save",
      "agent:run",
      "agent:cancel",
      "window:control",
    ]) ipcMain.removeHandler(channel);
  }

  private async bindDefault(projectPath: string): Promise<WorkspaceRecord> {
    const record = await this.registry.bindProject("default", path.resolve(projectPath));
    await this.services.get("default")?.close();
    this.services.delete("default");
    await this.ensureService(record);
    // 절대경로를 그대로 남기면 사용자 홈 디렉터리가 새어나간다(W7 공통 로그 정책 리뷰) -- 마지막 세그먼트만 기록.
    await this.logger.write("info", "workspace_project_bound", { workspaceId: "default", projectPath: basenameForLog(record.realProjectPath) });
    // EditorGateway(김민영 W4)가 editor_view_ready/unavailable을 pet-app에 보낼 수 있도록 알린다.
    this.emit("project-bound", record);
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
    const service = await FileService.create(record.realProjectPath, this.getEditableSizeLimit?.());
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

  sendAgentStatus(status: string): void {
    this.broadcast("agent:status", status);
  }

  sendWorkingPaths(paths: string[]): void {
    this.broadcast("agent:working-paths", paths);
  }
}
