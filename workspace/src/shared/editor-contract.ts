import type { JSONValue } from "@speaki-e/protocol";

export interface EditorMessage {
  requestId?: string;
  workspaceId: string;
  type: string;
  payload: JSONValue;
}

export interface EditorTransport {
  request<T extends JSONValue = JSONValue>(message: EditorMessage): Promise<T>;
  subscribe(listener: (message: EditorMessage) => void): () => void;
}

/**
 * 재연결 시 복원할 Editor View 상태 (열린 탭·활성 탭·ACP 작업 중 경로, plan/03_workspace.md 4.7).
 * main과 renderer 양쪽이 쓰므로 shared에 둔다.
 */
export interface EditorViewState {
  openTabs: string[];
  activePath?: string;
  workingPaths: string[];
}
