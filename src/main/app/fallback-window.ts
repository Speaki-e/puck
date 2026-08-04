import { app, BrowserWindow, dialog, screen } from "electron";
import path from "node:path";
import { normalizeWindowState, type WindowStateStore } from "../window-state-store.js";

export type PersistWindowState = () => Promise<void>;

/** Create the minimal Electron shell that hosts the same EditorGateway view as WKWebView. */
export async function createFallbackWindow(
  stateStore: WindowStateStore,
  editorUrl: string,
): Promise<PersistWindowState> {
  const state = normalizeWindowState(
    await stateStore.load(),
    screen.getAllDisplays().map((display) => display.workArea),
  );
  const window = new BrowserWindow({
    x: state.x,
    y: state.y,
    width: state.width,
    height: state.height,
    minWidth: 880,
    minHeight: 560,
    title: "Workspace",
    frame: process.platform !== "win32",
    autoHideMenuBar: true,
    backgroundColor: "#090909",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(app.getAppPath(), "dist-main", "main", "preload.cjs"),
    },
  });

  let saveTimer: NodeJS.Timeout | undefined;
  const persistBounds = () => {
    const bounds = window.getNormalBounds();
    return stateStore.save({ ...bounds, maximized: window.isMaximized() });
  };
  const scheduleBoundsSave = () => {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      saveTimer = undefined;
      void persistBounds();
    }, 250);
  };

  window.on("move", scheduleBoundsSave);
  window.on("resize", scheduleBoundsSave);
  window.on("maximize", scheduleBoundsSave);
  window.on("unmaximize", scheduleBoundsSave);
  window.on("close", () => {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = undefined;
    void persistBounds();
  });

  let forceClose = false;
  window.webContents.on("will-prevent-unload", (event) => {
    if (forceClose) return;
    event.preventDefault();
    const choice = dialog.showMessageBoxSync(window, {
      type: "warning",
      buttons: ["닫기", "취소"],
      defaultId: 1,
      cancelId: 1,
      message: "저장하지 않은 변경사항이 있습니다",
      detail: "지금 닫으면 저장하지 않은 변경 내용을 잃을 수 있습니다.",
    });
    if (choice === 0) {
      forceClose = true;
      window.close();
    }
  });

  window.setMenuBarVisibility(false);
  await window.loadURL(editorUrl);
  if (state.maximized) window.maximize();

  return () => window.isDestroyed() ? stateStore.flush() : persistBounds();
}
