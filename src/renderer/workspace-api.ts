import type { FileContent, FileTreeEntry, SaveFileRequest, SaveFileResult } from "../shared/file-contract";

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
  saveFile(workspaceId: string, request: SaveFileRequest): Promise<SaveFileResult>;
  runCommand(command: string, workspaceId: string): Promise<{ requestId: string }>;
  cancelCommand(): Promise<boolean>;
  windowControl(action: "minimize" | "maximize" | "close"): Promise<boolean>;
  onFileChange(listener: (event: FileChangeEvent) => void): () => void;
  onAgentStatus(listener: (status: string) => void): () => void;
}

declare global {
  interface Window {
    workspace?: WorkspaceApi;
  }
}
