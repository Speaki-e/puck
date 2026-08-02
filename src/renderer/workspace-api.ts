import type { FileContent, FileTreeEntry, SaveFileRequest, SaveFileResult } from "../shared/file-contract";
import type { EditorViewState } from "../shared/editor-contract";

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
}

declare global {
  interface Window {
    workspace?: WorkspaceApi;
  }
}
