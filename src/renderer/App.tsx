import Editor, { DiffEditor, type BeforeMount } from "@monaco-editor/react";
import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import type { FileTreeEntry } from "../shared/file-contract";
import { FileTree } from "./components/FileTree";
import { EditorTabs } from "./components/EditorTabs";
import { editorReducer, isDirty } from "./editor-state";
import type { RendererWorkspaceRecord } from "./workspace-api";
import { SettingsPanel } from "./components/SettingsPanel";
import { DRAFT_TTL_MS, draftKey, readDraft, removeDraft, type StoredDrafts, sweepExpiredDrafts } from "./draft-store";

const initialState = { tabs: [] };
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "gif", "webp"]);

function isImagePath(filePath: string): boolean {
  return IMAGE_EXTENSIONS.has(filePath.split(".").at(-1)?.toLowerCase() ?? "");
}

function Icon({ name }: { name: "folder" | "save" | "play" | "stop" | "sparkle" | "branch" | "gear" }) {
  const paths = {
    folder: <><path d="M3 5.5h5l1.5 2H21v10.5a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V7.5a2 2 0 0 1 2-2Z" /><path d="M1.5 9h20" /></>,
    save: <><path d="M4 3h13l3 3v15H4z" /><path d="M8 3v6h8V3M8 21v-7h8v7" /></>,
    play: <path d="m8 5 11 7-11 7Z" />,
    stop: <rect x="6" y="6" width="12" height="12" rx="2" />,
    sparkle: <><path d="m12 2 1.3 4.2A6 6 0 0 0 17.8 11L22 12l-4.2 1.3a6 6 0 0 0-4.5 4.5L12 22l-1.3-4.2a6 6 0 0 0-4.5-4.5L2 12l4.2-1.3a6 6 0 0 0 4.5-4.5Z" /></>,
    branch: <><circle cx="6" cy="5" r="2" /><circle cx="18" cy="6" r="2" /><circle cx="6" cy="19" r="2" /><path d="M6 7v10M8 8c2 5 8 1 8-1" /></>,
    gear: <><circle cx="12" cy="12" r="3" /><path d="M12 3v2M12 19v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M3 12h2M19 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4" /></>,
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
  // restoreState/saveState는 EditorGateway 경유 호스트(WKWebView 등)에서만 정의된다 -- 폴백
  // 셸(IPC)은 아래의 localStorage 초안 복구를 그대로 쓴다(W2 완료 기준: 재연결 시 탭 복원).
  const isGatewayHost = Boolean(api?.restoreState);
  const [workspace, setWorkspace] = useState<RendererWorkspaceRecord>();
  const [tree, setTree] = useState<FileTreeEntry[]>([]);
  const [state, dispatch] = useReducer(editorReducer, initialState);
  const [command, setCommand] = useState("");
  const [status, setStatus] = useState("준비됨");
  const [workingPaths, setWorkingPaths] = useState(() => new Set<string>());
  const [diffAgainstDisk, setDiffAgainstDisk] = useState<string>();
  const [settingsOpen, setSettingsOpen] = useState(false);
  const restoredProjects = useRef(new Set<string>());
  const active = state.tabs.find((tab) => tab.path === state.activePath);

  useEffect(() => setDiffAgainstDisk(undefined), [active?.path]);

  // 앱 시작 시 한 번 만료된 임시 복구 데이터를 정리한다(현재 열려는 프로젝트와 무관하게 전부 훑는다).
  useEffect(() => sweepExpiredDrafts(), []);

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
    // 게이트웨이 호스트는 아래 별도 effect가 state:restore로 탭을 복원한다 -- 여기서 또
    // dispatch("restore")를 하면 서로 덮어써서 충돌한다.
    if (isGatewayHost || !api || !workspace?.projectPath || restoredProjects.current.has(workspace.projectPath)) return;
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
  }, [api, workspace, isGatewayHost]);

  useEffect(() => {
    if (!isGatewayHost || !api?.restoreState || !workspace) return;
    let cancelled = false;
    void api.restoreState().then(async (restored) => {
      if (cancelled) return;
      if (restored.workingPaths.length) setWorkingPaths(new Set(restored.workingPaths));
      if (!restored.openTabs.length) return;
      const tabs = (await Promise.all(restored.openTabs.map(async (filePath) => {
        try {
          const file = isImagePath(filePath) ? await api.previewImage(workspace.id, filePath) : await api.readFile(workspace.id, filePath);
          return { ...file, savedContent: file.content, diskChanged: false };
        } catch {
          return undefined;
        }
      }))).filter((tab): tab is NonNullable<typeof tab> => Boolean(tab));
      if (!cancelled && tabs.length) {
        dispatch({ type: "restore", tabs, activePath: restored.activePath });
        setStatus(`재연결됨 -- ${tabs.length}개의 탭을 복원했습니다`);
      }
    });
    return () => { cancelled = true; };
  }, [api, workspace, isGatewayHost]);

  useEffect(() => {
    if (!isGatewayHost || !api?.saveState || !workspace) return;
    const timer = window.setTimeout(() => {
      api.saveState!({
        openTabs: state.tabs.map((tab) => tab.path),
        activePath: state.activePath,
        workingPaths: [...workingPaths],
      });
    }, 300);
    return () => window.clearTimeout(timer);
  }, [api, workspace, isGatewayHost, state.tabs, state.activePath, workingPaths]);

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

  const switchToRecentProject = async (projectPath: string) => {
    if (!api?.bindProject) return;
    const record = await api.bindProject(projectPath);
    setWorkspace(record);
    setTree(await api.listTree(record.id));
    setStatus(`${record.name} 프로젝트를 열었습니다`);
    setSettingsOpen(false);
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
    setDiffAgainstDisk(undefined);
  };

  const keepActiveMine = async () => {
    if (!active) return;
    // 저장 시 낙관적 잠금(expectedRevision)이 통과하도록, 내용은 그대로 두고 revision만 최신
    // 디스크 값으로 맞춘다 -- 안 하면 diskChanged를 내린 직후 저장이 file_conflict로 다시 막힌다.
    if (api && workspace && !active.previewUrl) {
      try {
        const disk = await api.readFile(workspace.id, active.path);
        dispatch({ type: "keepMine", path: active.path, revision: disk.revision });
        setDiffAgainstDisk(undefined);
        return;
      } catch {
        // 아래 폴백으로 진행
      }
    }
    dispatch({ type: "keepMine", path: active.path });
    setDiffAgainstDisk(undefined);
  };

  const showDiffAgainstDisk = async () => {
    if (!api || !workspace || !active || active.previewUrl) return;
    try {
      const disk = await api.readFile(workspace.id, active.path);
      setDiffAgainstDisk(disk.content);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "디스크 내용을 불러오지 못했습니다");
    }
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
          {api?.getSettings && (
            <button type="button" className="button-ghost" onClick={() => setSettingsOpen(true)} aria-label="설정">
              <Icon name="gear" />
            </button>
          )}
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
                    {!active.previewUrl && (
                      <button
                        type="button"
                        className="button-ghost"
                        onClick={() => (diffAgainstDisk === undefined ? void showDiffAgainstDisk() : setDiffAgainstDisk(undefined))}
                      >
                        {diffAgainstDisk === undefined ? "diff 비교" : "diff 닫기"}
                      </button>
                    )}
                    <button type="button" className="button-ghost" onClick={() => void reloadActive()}>디스크 내용 사용</button>
                    <button type="button" className="button-primary-small" onClick={() => void keepActiveMine()}>내 내용 유지</button>
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
                ) : diffAgainstDisk !== undefined ? (
                  <DiffEditor
                    original={diffAgainstDisk}
                    modified={active.content}
                    language={active.language}
                    theme="workspace-dark"
                    beforeMount={configureMonaco}
                    options={{
                      readOnly: true,
                      renderSideBySide: true,
                      automaticLayout: true,
                      fontFamily: "'Geist Mono', 'SFMono-Regular', Consolas, monospace",
                      fontSize: 13,
                    }}
                  />
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
      {settingsOpen && api && (
        <SettingsPanel api={api} onClose={() => setSettingsOpen(false)} onProjectSelected={(path) => void switchToRecentProject(path)} />
      )}
    </main>
  );
}
