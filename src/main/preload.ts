import { contextBridge } from "electron";

contextBridge.exposeInMainWorld("workspace", {
  platform: process.platform,
});
