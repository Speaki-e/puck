import Editor, { type BeforeMount } from "@monaco-editor/react";
import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import type { FileTreeEntry } from "../shared/file-contract";
import { FileTree } from "./components/FileTree";
import { EditorTabs } from "./components/EditorTabs";
import { editorReducer, isDirty } from "./editor-state";
import type { RendererWorkspaceRecord } from "./workspace-api";

const initialState = { tabs: [] };
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "gif", "webp"]);
const DRAFT_TTL_MS = 7 * 24 * 60 * 60 * 1_000;

interface StoredDrafts {
  projectPath: string;
  expiresAt: number;
  activePath?: string;
  tabs: Array<{ path: string; content: string; revision: string }>;
}

function isImagePath(filePath: string): boolean {
  return IMAGE_EXTENSIONS.has(filePath.split(".").at(-1)?.toLowerCase() ?? "");
}

function draftKey(projectPath: string): string {
  return `workspace:drafts:${projectPath}`;
}

function readDraft(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function removeDraft(key: string): void {
  try {
    localStorage.removeItem(key);
  } catch {
    // Draft recovery is best-effort and must never break the editor.
  }
}

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
  monaco.editor.defineTheme("workspace-dark", {
    base: "vs-dark",
    inherit: true,
    rules: [
      { token: "comment", foreground: "737373", fontStyle: "italic" },
      { token: "keyword", foreground: "C084FC" },
      { token: "string", foreground: "7DD3FC" },
      { token: "number", foreground: "FBBF24" },
      { token: "type", foreground: "60A5FA" },
    ],
    colors: {
      "editor.background": "#101010",
      "editor.foreground": "#e7e7e7",
      "editorLineNumber.foreground": "#4f4f4f",
      "editorLineNumber.activeForeground": "#a3a3a3",
      "editor.lineHighlightBackground": "#151515",
      "editor.selectionBackground": "#173f70",
      "editor.inactiveSelectionBackground": "#182c43",
      "editorIndentGuide.background1": "#252525",
      "editorIndentGuide.activeBackground1": "#404040",
      "editorCursor.foreground": "#f5f5f5",
      "editorWhitespace.foreground": "#292929",
      "editorGutter.background": "#101010",
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
  const [workingPaths, setWorkingPaths] = useState(() => new Set<string>());
  const restoredProjects = useRef(new Set<string>());
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
  useEffect(() => api?.onWorkingPaths((paths) => setWorkingPaths(new Set(paths))), [api]);

  useEffect(() => {
    if (!api || !workspace?.projectPath || restoredProjects.current.has(workspace.projectPath)) return;
    restoredProjects.current.add(workspace.projectPath);
    const key = draftKey(workspace.projectPath);
    const raw = readDraft(key);
    if (!raw) return;
    let stored: StoredDrafts;
    try {
      stored = JSON.parse(raw) as StoredDrafts;
    } catch {
      removeDraft(key);
      return;
    }
    if (stored.projectPath !== workspace.projectPath || stored.expiresAt < Date.now() || !Array.isArray(stored.tabs)) {
      removeDraft(key);
      return;
    }
    let cancelled = false;
    void Promise.all(stored.tabs.map(async (draft) => {
      try {
        const disk = await api.readFile(workspace.id, draft.path);
        return {
          ...disk,
          content: draft.content,
          savedContent: disk.content,
          diskChanged: disk.revision !== draft.revision,
        };
      } catch {
        return undefined;
      }
    })).then((tabs) => {
      const restored = tabs.filter((tab): tab is NonNullable<typeof tab> => Boolean(tab));
      if (!cancelled && restored.length) {
        dispatch({ type: "restore", tabs: restored, activePath: stored.activePath });
        setStatus(`${restored.length}개의 미저장 파일을 복구했습니다`);
      }
    });
    return () => { cancelled = true; };
  }, [api, workspace]);

  useEffect(() => {
    if (!workspace?.projectPath || !restoredProjects.current.has(workspace.projectPath)) return;
    const timer = window.setTimeout(() => {
      const dirtyTabs = state.tabs.filter((tab) => isDirty(tab) && !tab.previewUrl);
      const key = draftKey(workspace.projectPath!);
      if (!dirtyTabs.length) {
        removeDraft(key);
        return;
      }
      const payload: StoredDrafts = {
        projectPath: workspace.projectPath!,
        expiresAt: Date.now() + DRAFT_TTL_MS,
        activePath: dirtyTabs.some((tab) => tab.path === state.activePath) ? state.activePath : dirtyTabs.at(-1)?.path,
        tabs: dirtyTabs.map((tab) => ({ path: tab.path, content: tab.content, revision: tab.revision })),
      };
      try {
        localStorage.setItem(key, JSON.stringify(payload));
      } catch {
        setStatus("미저장 복구 데이터를 저장할 공간이 부족합니다");
      }
    }, 300);
    return () => window.clearTimeout(timer);
  }, [state, workspace]);

  useEffect(() => {
    const beforeUnload = (event: BeforeUnloadEvent) => {
      if (!state.tabs.some(isDirty)) return;
      event.preventDefault();
    };
    window.addEventListener("beforeunload", beforeUnload);
    return () => window.removeEventListener("beforeunload", beforeUnload);
  }, [state.tabs]);

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
      const file = isImagePath(filePath)
        ? await api.previewImage(workspace.id, filePath)
        : await api.readFile(workspace.id, filePath);
      dispatch({ type: "open", file });
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
    if (!api || !workspace || !active) return;
    const file = active.previewUrl
      ? await api.previewImage(workspace.id, active.path)
      : await api.readFile(workspace.id, active.path);
    dispatch({ type: "reload", file });
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
          <span className="brand-mark" aria-hidden>
            <svg viewBox="0 0 24 24" fill="none">
              <circle cx="6" cy="7" r="2.25" />
              <circle cx="18" cy="7" r="2.25" />
              <circle cx="12" cy="17" r="2.25" />
              <path d="M8 8.2 10.8 15M16 8.2 13.2 15M8.2 7h7.6" />
            </svg>
          </span>
          <span className="brand-name">Workspace</span>
          <span className="alpha-badge">ALPHA</span>
        </div>
        <div className="project-identity" title={workspace?.projectPath}>
          <span className={`project-dot ${workspace ? "connected" : ""}`} />
          <strong>{title}</strong>
          <span className="project-path">{workspace?.projectPath ?? "프로젝트가 연결되지 않음"}</span>
        </div>
        <div className="titlebar-actions">
          <button type="button" className="button-ghost project-button" onClick={() => void openProject()}>
            <Icon name="folder" /> 프로젝트 열기
          </button>
          {api?.platform === "win32" && (
            <div className="window-actions" aria-label="창 제어">
              <button type="button" onClick={() => void api.windowControl("minimize")} aria-label="창 최소화"><span className="minimize-symbol" /></button>
              <button type="button" onClick={() => void api.windowControl("maximize")} aria-label="창 최대화"><span className="maximize-symbol" /></button>
              <button type="button" className="window-close" onClick={() => void api.windowControl("close")} aria-label="창 닫기"><span className="close-symbol" /></button>
            </div>
          )}
        </div>
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
                {active.previewUrl ? (
                  <div className="image-preview">
                    <div className="image-preview-canvas">
                      <img src={active.previewUrl} alt={active.path.split("/").at(-1)} />
                    </div>
                    <div className="image-metadata">
                      <strong>{active.path.split("/").at(-1)}</strong>
                      <span>{active.mimeType}</span>
                      <span>{Math.max(1, Math.round(active.size / 1024))} KB</span>
                    </div>
                  </div>
                ) : <Editor
                  path={active.path}
                  value={active.content}
                  language={active.language}
                  theme="workspace-dark"
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
                />}
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
