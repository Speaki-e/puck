import type { FileContent, FileTreeEntry, SaveFileRequest, SaveFileResult } from "../shared/file-contract";
import type { EditorViewState } from "../shared/editor-contract";
import type { SettingsSnapshot, WorkspaceSettings } from "../shared/settings-contract";

export interface RendererWorkspaceRecord {
  id: string;
  name: string;
  projectPath?: string;
}

export interface FileChangeEvent {
  event: "add" | "change" | "unlink" | "addDir" | "unlinkDir";
  path: string;
}

export interface WorkspaceApi {
  platform: string;
  selectProject(): Promise<RendererWorkspaceRecord | undefined>;
  currentWorkspace(): Promise<RendererWorkspaceRecord | undefined>;
  /** 설정 화면의 "최근 프로젝트"에서 다이얼로그 없이 바로 전환하기 위한 선택적 확장(폴백 셸 전용). */
  bindProject?(projectPath: string): Promise<RendererWorkspaceRecord>;
  listTree(workspaceId: string): Promise<FileTreeEntry[]>;
  readFile(workspaceId: string, path: string): Promise<FileContent>;
  previewImage(workspaceId: string, path: string): Promise<FileContent>;
  saveFile(workspaceId: string, request: SaveFileRequest): Promise<SaveFileResult>;
  runCommand(command: string, workspaceId: string): Promise<{ requestId: string }>;
  cancelCommand(): Promise<boolean>;
  windowControl(action: "minimize" | "maximize" | "close"): Promise<boolean>;
  onFileChange(listener: (event: FileChangeEvent) => void): () => void;
  onAgentStatus(listener: (status: string) => void): () => void;
  onWorkingPaths(listener: (paths: string[]) => void): () => void;
  /**
   * EditorGateway 재연결 시 열린 탭·활성 탭·작업 경로를 복원하기 위한 선택적 확장(W2 완료 기준).
   * WKWebView/게이트웨이 호스트에서만 의미가 있다 -- 폴백 셸(IPC)은 자체 localStorage 초안 복구를
   * 이미 갖고 있어(App.tsx) 구현하지 않아도 된다.
   */
  restoreState?(): Promise<EditorViewState>;
  saveState?(state: EditorViewState): void;
  /**
   * 설정 화면(W7)용 선택적 확장 -- 폴백 셸(IPC)에서만 노출한다(plan 4.5: pet-app 쪽 설정은
   * 02_pet-app.md 몫). 게이트웨이 호스트(WKWebView)에는 구현하지 않는다.
   */
  getSettings?(): Promise<SettingsSnapshot>;
  updateSettings?(patch: Partial<WorkspaceSettings>): Promise<SettingsSnapshot>;
  setApiKey?(key: string): Promise<{ hasApiKey: boolean }>;
  clearApiKey?(): Promise<{ hasApiKey: boolean }>;
}

declare global {
  interface Window {
    workspace?: WorkspaceApi;
  }
}
