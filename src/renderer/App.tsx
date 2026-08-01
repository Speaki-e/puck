import Editor from "@monaco-editor/react";
import { useCallback, useEffect, useMemo, useReducer, useState } from "react";
import type { FileTreeEntry } from "../shared/file-contract";
import { FileTree } from "./components/FileTree";
import { EditorTabs } from "./components/EditorTabs";
import { editorReducer, isDirty } from "./editor-state";
import type { RendererWorkspaceRecord } from "./workspace-api";

const initialState = { tabs: [] };

export function App() {
  const api = window.workspace;
  const [workspace, setWorkspace] = useState<RendererWorkspaceRecord>();
  const [tree, setTree] = useState<FileTreeEntry[]>([]);
  const [state, dispatch] = useReducer(editorReducer, initialState);
  const [command, setCommand] = useState("");
  const [status, setStatus] = useState("준비됨");
  const [workingPaths] = useState(() => new Set<string>());
  const active = state.tabs.find((tab) => tab.path === state.activePath);

  const refreshTree = useCallback(async (record: RendererWorkspaceRecord) => {
    if (!api) return;
    setTree(await api.listTree(record.id));
  }, [api]);

  useEffect(() => {
    void api?.currentWorkspace().then((record) => {
      if (record?.projectPath) {
        setWorkspace(record);
        void refreshTree(record);
      }
    });
  }, [api, refreshTree]);

  useEffect(() => api?.onFileChange((event) => {
    const tab = state.tabs.find((item) => item.path === event.path);
    if (event.event === "change" && tab) dispatch({ type: "diskChanged", path: event.path });
    if (workspace) void refreshTree(workspace);
  }), [api, refreshTree, state.tabs, workspace]);

  useEffect(() => api?.onAgentStatus(setStatus), [api]);

  const openProject = async () => {
    const record = await api?.selectProject();
    if (!record) return;
    setWorkspace(record);
    setTree(await api!.listTree(record.id));
  };

  const openFile = async (filePath: string) => {
    if (!api || !workspace) return;
    try {
      dispatch({ type: "open", file: await api.readFile(workspace.id, filePath) });
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "파일을 열 수 없습니다");
    }
  };

  const saveActive = useCallback(async () => {
    if (!api || !workspace || !active || active.readOnly || !isDirty(active)) return;
    try {
      const result = await api.saveFile(workspace.id, {
        path: active.path,
        content: active.content,
        expectedRevision: active.revision,
      });
      dispatch({ type: "saved", path: active.path, revision: result.revision, size: result.size });
      setStatus(`${active.path} 저장됨`);
    } catch (error) {
      dispatch({ type: "diskChanged", path: active.path });
      setStatus(error instanceof Error ? error.message : "저장하지 못했습니다");
    }
  }, [active, api, workspace]);

  useEffect(() => {
    const listener = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        void saveActive();
      }
    };
    window.addEventListener("keydown", listener);
    return () => window.removeEventListener("keydown", listener);
  }, [saveActive]);

  const reloadActive = async () => {
    if (!api || !workspace || !active) return;
    dispatch({ type: "reload", file: await api.readFile(workspace.id, active.path) });
  };

  const runCommand = async () => {
    if (!api || !workspace || !command.trim()) return;
    setStatus("작업을 시작하는 중...");
    await api.runCommand(command.trim(), workspace.id);
    setCommand("");
  };

  const title = useMemo(() => workspace?.projectPath?.split(/[\\/]/).at(-1) ?? "Workspace", [workspace]);

  return (
    <main className="workspace-shell">
      <header className="titlebar">
        <strong>{title}</strong>
        <button type="button" onClick={() => void openProject()}>프로젝트 열기</button>
      </header>
      <section className="editor-layout">
        <aside className="sidebar">
          <div className="sidebar-title">파일</div>
          <FileTree entries={tree} activePath={state.activePath} workingPaths={workingPaths} onOpen={(path) => void openFile(path)} />
        </aside>
        <section className="editor-pane">
          <EditorTabs
            tabs={state.tabs}
            activePath={state.activePath}
            onActivate={(path) => dispatch({ type: "activate", path })}
            onClose={(path) => {
              const tab = state.tabs.find((item) => item.path === path);
              if (!tab || !isDirty(tab) || window.confirm("저장하지 않은 변경을 닫을까요?")) dispatch({ type: "close", path });
            }}
          />
          {active ? (
            <>
              {active.diskChanged && (
                <div className="conflict-banner">
                  <span>디스크의 파일이 변경되었습니다.</span>
                  <button type="button" onClick={() => void reloadActive()}>디스크 내용으로 다시 열기</button>
                  <button type="button" onClick={() => dispatch({ type: "keepMine", path: active.path })}>내 내용 유지</button>
                  <button type="button" disabled title="diff는 후속 통합에서 제공됩니다">diff 비교</button>
                </div>
              )}
              <Editor
                path={active.path}
                value={active.content}
                language={active.language}
                theme="vs-dark"
                onChange={(value) => dispatch({ type: "edit", path: active.path, content: value ?? "" })}
                options={{
                  readOnly: active.readOnly,
                  automaticLayout: true,
                  minimap: { enabled: false },
                  fontSize: 14,
                  padding: { top: 12 },
                  scrollBeyondLastLine: false,
                }}
              />
            </>
          ) : (
            <div className="empty-editor">
              <h2>파일을 선택하세요</h2>
              <p>좌측 프로젝트 트리에서 편집할 파일을 열 수 있습니다.</p>
            </div>
          )}
        </section>
      </section>
      <footer className="command-bar">
        <span className="status-indicator" aria-label="현재 상태">{status}</span>
        <input
          value={command}
          onChange={(event) => setCommand(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Enter") void runCommand(); }}
          placeholder="한 줄 명령을 입력하세요"
          aria-label="에이전트 명령"
        />
        <button type="button" onClick={() => void runCommand()} disabled={!workspace || !command.trim()}>실행</button>
        <button type="button" className="danger" onClick={() => void api?.cancelCommand()}>중지</button>
      </footer>
    </main>
  );
}
