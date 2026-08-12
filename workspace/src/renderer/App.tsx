import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import type { FileTreeEntry } from "../shared/file-contract";
import { CommandDock } from "./components/CommandDock";
import { EditorSurface } from "./components/EditorSurface";
import { EditorTabs } from "./components/EditorTabs";
import { FileTree } from "./components/FileTree";
import { Icon } from "./components/Icon";
import { SettingsPanel } from "./components/SettingsPanel";
import { WorkspaceTitlebar } from "./components/WorkspaceTitlebar";
import { DRAFT_TTL_MS, draftKey, readDraft, removeDraft, type StoredDrafts, sweepExpiredDrafts } from "./draft-store";
import { editorReducer, isDirty } from "./editor-state";
import type { RendererWorkspaceRecord } from "./workspace-api";

const initialState = { tabs: [] };
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "gif", "webp"]);

function isImagePath(filePath: string): boolean {
  return IMAGE_EXTENSIONS.has(filePath.split(".").at(-1)?.toLowerCase() ?? "");
}

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
  const dirtyCount = state.tabs.filter(isDirty).length;

  return (
    <main className="workspace-shell">
      <WorkspaceTitlebar
        api={api}
        title={title}
        projectPath={workspace?.projectPath}
        connected={Boolean(workspace)}
        onOpenProject={() => void openProject()}
        onOpenSettings={() => setSettingsOpen(true)}
      />

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

          <EditorSurface
            active={active}
            diffAgainstDisk={diffAgainstDisk}
            onEdit={(content) => active && dispatch({ type: "edit", path: active.path, content })}
            onSave={() => void saveActive()}
            onToggleDiff={() => (
              diffAgainstDisk === undefined
                ? void showDiffAgainstDisk()
                : setDiffAgainstDisk(undefined)
            )}
            onReload={() => void reloadActive()}
            onKeepMine={() => void keepActiveMine()}
            onOpenProject={() => void openProject()}
          />
        </section>
      </section>

      <CommandDock
        status={status}
        command={command}
        enabled={Boolean(workspace)}
        onCommandChange={setCommand}
        onRun={() => void runCommand()}
        onCancel={() => void api?.cancelCommand()}
      />
      {settingsOpen && api && (
        <SettingsPanel api={api} onClose={() => setSettingsOpen(false)} onProjectSelected={(path) => void switchToRecentProject(path)} />
      )}
    </main>
  );
}
