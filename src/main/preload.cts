const { contextBridge, ipcRenderer } = require("electron") as typeof import("electron");

contextBridge.exposeInMainWorld("workspace", {
  platform: process.platform,
  selectProject: () => ipcRenderer.invoke("workspace:select-project"),
  currentWorkspace: () => ipcRenderer.invoke("workspace:current"),
  listTree: (workspaceId: string) => ipcRenderer.invoke("files:list-tree", workspaceId),
  readFile: (workspaceId: string, filePath: string) => ipcRenderer.invoke("files:read", workspaceId, filePath),
  saveFile: (workspaceId: string, request: unknown) => ipcRenderer.invoke("files:save", workspaceId, request),
  runCommand: (command: string, workspaceId: string) => ipcRenderer.invoke("agent:run", command, workspaceId),
  cancelCommand: () => ipcRenderer.invoke("agent:cancel"),
  onFileChange: (listener: (event: unknown) => void) => {
    const wrapped = (_event: Electron.IpcRendererEvent, payload: unknown) => listener(payload);
    ipcRenderer.on("files:changed", wrapped);
    return () => ipcRenderer.removeListener("files:changed", wrapped);
  },
  onAgentStatus: (listener: (status: string) => void) => {
    const wrapped = (_event: Electron.IpcRendererEvent, payload: string) => listener(payload);
    ipcRenderer.on("agent:status", wrapped);
    return () => ipcRenderer.removeListener("agent:status", wrapped);
  },
});
