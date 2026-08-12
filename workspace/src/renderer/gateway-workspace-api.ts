import type { JSONValue } from "@speaki-e/protocol";
import type { EditorMessage, EditorTransport, EditorViewState } from "../shared/editor-contract";
import type { FileContent, FileTreeEntry, SaveFileRequest, SaveFileResult } from "../shared/file-contract";
import type { FileChangeEvent, RendererWorkspaceRecord, WorkspaceApi } from "./workspace-api";

/**
 * EditorTransport.request<T>는 T가 JSONValue를 extend해야 하지만, FileTreeEntry 등은 인덱스
 * 시그니처가 없는 평범한 interface라 그 제약을 구조적으로 만족하지 못한다. wire 위에서는 이미
 * JSON이므로 여기서만 캐스팅해 흡수한다.
 */
function requestAs<T>(transport: EditorTransport, message: EditorMessage): Promise<T> {
  return transport.request(message) as Promise<T>;
}

/**
 * pet-app WKWebView(또는 그 밖의 contextBridge 없는 호스트)용 WorkspaceApi 구현.
 * main.tsx가 window.workspace(폴백 셸의 IPC 버전)가 없을 때만 이걸 설치한다 -- App.tsx는
 * 어느 쪽이 붙어 있는지 몰라도 되고, 트랜스포트만 다르다(plan/03_workspace.md 4.1).
 * 프로젝트 선택/명령 실행/창 제어는 이 호스트의 몫이 아니라서(채팅은 pet-app이, 창은 pet-app이나
 * 폴백 셸이 각자 관리) 지원하지 않는다.
 */
export function createGatewayWorkspaceApi(transport: EditorTransport, workspaceId: string): WorkspaceApi {
  return {
    platform: "gateway",

    async selectProject() {
      return undefined;
    },

    async currentWorkspace(): Promise<RendererWorkspaceRecord | undefined> {
      try {
        await transport.request({ workspaceId, type: "file:list-tree", payload: null });
        return { id: workspaceId, name: workspaceId, projectPath: workspaceId };
      } catch {
        return undefined;
      }
    },

    listTree(id) {
      return requestAs<FileTreeEntry[]>(transport, { workspaceId: id, type: "file:list-tree", payload: null });
    },

    readFile(id, filePath) {
      return requestAs<FileContent>(transport, { workspaceId: id, type: "file:read", payload: { path: filePath } });
    },

    previewImage(id, filePath) {
      return requestAs<FileContent>(transport, { workspaceId: id, type: "file:preview-image", payload: { path: filePath } });
    },

    saveFile(id, request: SaveFileRequest) {
      return requestAs<SaveFileResult>(transport, { workspaceId: id, type: "file:save", payload: request as unknown as JSONValue });
    },

    async runCommand(): Promise<{ requestId: string }> {
      throw new Error("Editor View에서는 에이전트 명령을 직접 실행하지 않습니다 -- pet-app 채팅을 사용하세요");
    },

    async cancelCommand() {
      return false;
    },

    async windowControl() {
      return false;
    },

    onFileChange(listener: (event: FileChangeEvent) => void) {
      return transport.subscribe((message) => {
        if (message.type === "file:changed") listener(message.payload as unknown as FileChangeEvent);
      });
    },

    onAgentStatus() {
      return () => undefined;
    },

    onWorkingPaths(listener: (paths: string[]) => void) {
      return transport.subscribe((message) => {
        if (message.type === "acp:working-paths") listener(message.payload as unknown as string[]);
      });
    },

    /** 재연결 시 열린 탭·활성 탭·작업 경로를 복원하기 위한 진입점(W2 완료 기준). */
    restoreState() {
      return requestAs<EditorViewState>(transport, { workspaceId, type: "state:restore", payload: null });
    },

    saveState(state: EditorViewState) {
      void transport.request({ workspaceId, type: "state:update", payload: state as unknown as JSONValue }).catch(() => undefined);
    },
  };
}
