import { app, BrowserWindow } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonlLogger } from "./logger.js";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const isHeadless = process.argv.includes("--headless");

async function createFallbackWindow(): Promise<void> {
  const window = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 880,
    minHeight: 560,
    title: "Workspace",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(currentDirectory, "preload.js"),
    },
  });
  await window.loadFile(path.join(app.getAppPath(), "dist", "index.html"));
}

await app.whenReady();
const logger = new JsonlLogger(path.join(app.getPath("userData"), "logs"));
await logger.write("info", "workspace_started", { headless: isHeadless });

if (!isHeadless) await createFallbackWindow();

app.on("window-all-closed", () => {
  if (!isHeadless) app.quit();
});
