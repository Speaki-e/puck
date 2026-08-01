import Editor, { type BeforeMount } from "@monaco-editor/react";
import { useCallback, useEffect, useMemo, useReducer, useState } from "react";
import type { FileTreeEntry } from "../shared/file-contract";
import { FileTree } from "./components/FileTree";
import { EditorTabs } from "./components/EditorTabs";
import { editorReducer, isDirty } from "./editor-state";
import type { RendererWorkspaceRecord } from "./workspace-api";

const initialState = { tabs: [] };

function Icon({ name }: { name: "folder" | "save" | "play" | "stop" | "sparkle" | "branch" }) {
  const paths = {
    folder: <><path d="M3 5.5h5l1.5 2H21v10.5a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V7.5a2 2 0 0 1 2-2Z" /><path d="M1.5 9h20" /></>,
    save: <><path d="M4 3h13l3 3v15H4z" /><path d="M8 3v6h8V3M8 21v-7h8v7" /></>,
    play: <path d="m8 5 11 7-11 7Z" />,
    stop: <rect x="6" y="6" width="12" height="12" rx="2" />,
    sparkle: <><path d="m12 2 1.3 4.2A6 6 0 0 0 17.8 11L22 12l-4.2 1.3a6 6 0 0 0-4.5 4.5L12 22l-1.3-4.2a6 6 0 0 0-4.5-4.5L2 12l4.2-1.3a6 6 0 0 0 4.5-4.5Z" /></>,
    branch: <><circle cx="6" cy="5" r="2" /><circle cx="18" cy="6" r="2" /><circle cx="6" cy="19" r="2" /><path d="M6 7v10M8 8c2 5 8 1 8-1" /></>,
  };
  return <svg className="icon" viewBox="0 0 24 24" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{paths[name]}</svg>;
}

const configureMonaco: BeforeMount = (monaco) => {
  monaco.editor.defineTheme("workspace-light", {
    base: "vs",
    inherit: true,
    rules: [
      { token: "comment", foreground: "8f8f8f", fontStyle: "italic" },
      { token: "keyword", foreground: "7928ca" },
      { token: "string", foreground: "0761d1" },
      { token: "number", foreground: "ab570a" },
      { token: "type", foreground: "0070f3" },
    ],
    colors: {
      "editor.background": "#ffffff",
      "editor.foreground": "#171717",
      "editorLineNumber.foreground": "#b7b7b7",
      "editorLineNumber.activeForeground": "#4d4d4d",
      "editor.lineHighlightBackground": "#fafafa",
      "editor.selectionBackground": "#d3e5ff",
      "editor.inactiveSelectionBackground": "#edf4ff",
      "editorIndentGuide.background1": "#f0f0f0",
      "editorIndentGuide.activeBackground1": "#d5d5d5",
      "editorCursor.foreground": "#171717",
      "editorWhitespace.foreground": "#e8e8e8",
      "editorGutter.background": "#ffffff",
    },
  });
};

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
    if (api) setTree(await api.listTree(record.id));
  }, [api]);

  useEffect(() => {
    void api?.currentWorkspace().then((record) => {
      if (!record?.projectPath) return;
      setWorkspace(record);
      void refreshTree(record);
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
    setStatus(`${record.name} 프로젝트를 열었습니다`);
  };

  const openFile = async (filePath: string) => {
    if (!api || !workspace) return;
    try {
      dispatch({ type: "open", file: await api.readFile(workspace.id, filePath) });
      setStatus(filePath);
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
    if (api && workspace && active) dispatch({ type: "reload", file: await api.readFile(workspace.id, active.path) });
  };

  const runCommand = async () => {
    if (!api || !workspace || !command.trim()) return;
    setStatus("Agent가 작업을 시작하는 중…");
    await api.runCommand(command.trim(), workspace.id);
    setCommand("");
  };

  const title = useMemo(() => workspace?.projectPath?.split(/[\\/]/).at(-1) ?? "Workspace", [workspace]);
  const breadcrumbs = active?.path.split("/") ?? [];
  const dirtyCount = state.tabs.filter(isDirty).length;

  return (
    <main className="workspace-shell">
      <header className="titlebar">
        <div className="brand-lockup">
          <span className="brand-mark" aria-hidden><span /></span>
          <span className="brand-name">Workspace</span>
          <span className="alpha-badge">ALPHA</span>
        </div>
        <div className="project-identity" title={workspace?.projectPath}>
          <span className={`project-dot ${workspace ? "connected" : ""}`} />
          <strong>{title}</strong>
          <span className="project-path">{workspace?.projectPath ?? "프로젝트가 연결되지 않음"}</span>
        </div>
        <button type="button" className="button-ghost project-button" onClick={() => void openProject()}>
          <Icon name="folder" /> 프로젝트 열기
        </button>
      </header>

      <section className="editor-layout">
        <aside className="sidebar">
          <div className="sidebar-heading">
            <div>
              <span className="eyebrow">PROJECT</span>
              <h2>Explorer</h2>
            </div>
            <span className="file-count">{tree.length}</span>
          </div>
          <FileTree entries={tree} activePath={state.activePath} workingPaths={workingPaths} onOpen={(filePath) => void openFile(filePath)} />
          <div className="sidebar-footer">
            <Icon name="branch" />
            <span>main</span>
            <span className="sidebar-spacer" />
            <span>{dirtyCount ? `${dirtyCount} unsaved` : "clean"}</span>
          </div>
        </aside>

        <section className="editor-pane">
          <EditorTabs
            tabs={state.tabs}
            activePath={state.activePath}
            onActivate={(filePath) => dispatch({ type: "activate", path: filePath })}
            onClose={(filePath) => {
              const tab = state.tabs.find((item) => item.path === filePath);
              if (!tab || !isDirty(tab) || window.confirm("저장하지 않은 변경을 닫을까요?")) dispatch({ type: "close", path: filePath });
            }}
          />

          <div className="editor-toolbar">
            <nav className="breadcrumbs" aria-label="현재 파일 경로">
              {breadcrumbs.length ? breadcrumbs.map((part, index) => (
                <span key={`${part}-${index}`} className={index === breadcrumbs.length - 1 ? "current" : ""}>
                  {part}{index < breadcrumbs.length - 1 && <b>/</b>}
                </span>
              )) : <span className="muted">파일을 선택하세요</span>}
            </nav>
            {active && <span className="language-badge">{active.language}</span>}
            {active?.readOnly && <span className="readonly-badge">READ ONLY</span>}
            <button
              type="button"
              className="button-ghost save-button"
              onClick={() => void saveActive()}
              disabled={!active || active.readOnly || !isDirty(active)}
              title="저장 (Ctrl/Cmd + S)"
            >
              <Icon name="save" /> 저장
            </button>
          </div>

          <div className="editor-stage">
            {active ? (
              <>
                {active.diskChanged && (
                  <div className="conflict-banner" role="alert">
                    <div className="conflict-symbol">!</div>
                    <div className="conflict-copy">
                      <strong>디스크에서 파일이 변경됐습니다</strong>
                      <span>저장하기 전에 사용할 버전을 선택하세요.</span>
                    </div>
                    <button type="button" className="button-ghost" onClick={() => void reloadActive()}>디스크 내용 사용</button>
                    <button type="button" className="button-primary-small" onClick={() => dispatch({ type: "keepMine", path: active.path })}>내 내용 유지</button>
                  </div>
                )}
                <Editor
                  path={active.path}
                  value={active.content}
                  language={active.language}
                  theme="workspace-light"
                  beforeMount={configureMonaco}
                  onChange={(value) => dispatch({ type: "edit", path: active.path, content: value ?? "" })}
                  options={{
                    readOnly: active.readOnly,
                    automaticLayout: true,
                    minimap: { enabled: true, renderCharacters: false, maxColumn: 90, scale: 0.8 },
                    fontFamily: "'Geist Mono', 'SFMono-Regular', Consolas, monospace",
                    fontSize: 13,
                    lineHeight: 21,
                    fontLigatures: true,
                    padding: { top: 20, bottom: 20 },
                    scrollBeyondLastLine: false,
                    smoothScrolling: true,
                    cursorSmoothCaretAnimation: "on",
                    bracketPairColorization: { enabled: true },
                    guides: { bracketPairs: true, indentation: true },
                    renderLineHighlight: "all",
                    overviewRulerBorder: false,
                  }}
                />
              </>
            ) : (
              <div className="empty-editor">
                <div className="mesh-orb" aria-hidden><span /><span /><span /></div>
                <span className="eyebrow">LIGHTWEIGHT CODE WORKSPACE</span>
                <h1>프로젝트를 열고,<br />아이디어를 코드로 만드세요.</h1>
                <p>왼쪽 탐색기에서 파일을 선택하거나 Agent에게<br />원하는 변경을 자연어로 요청할 수 있습니다.</p>
                <div className="empty-actions">
                  <button type="button" className="button-primary" onClick={() => void openProject()}><Icon name="folder" /> 프로젝트 열기</button>
                  <span><kbd>Ctrl</kbd><b>+</b><kbd>S</kbd> 빠른 저장</span>
                </div>
              </div>
            )}
          </div>
        </section>
      </section>

      <footer className="command-dock">
        <div className="status-block">
          <span className="status-pulse" />
          <div>
            <span className="eyebrow">STATUS</span>
            <span className="status-text" aria-label="현재 상태">{status}</span>
          </div>
        </div>
        <div className="command-composer">
          <span className="composer-icon"><Icon name="sparkle" /></span>
          <input
            value={command}
            onChange={(event) => setCommand(event.target.value)}
            onKeyDown={(event) => { if (event.key === "Enter") void runCommand(); }}
            placeholder={workspace ? "Agent에게 코드 작업을 요청하세요…" : "먼저 프로젝트를 열어주세요"}
            aria-label="에이전트 명령"
            disabled={!workspace}
          />
          <span className="enter-hint">ENTER</span>
          <button type="button" className="run-button" onClick={() => void runCommand()} disabled={!workspace || !command.trim()} aria-label="명령 실행"><Icon name="play" /></button>
        </div>
        <button type="button" className="stop-button" onClick={() => void api?.cancelCommand()}><Icon name="stop" /> 중지</button>
      </footer>
    </main>
  );
}
