import { app } from "electron";
import { startWorkspaceApplication } from "./app/workspace-application.js";

void startWorkspaceApplication().catch((error) => {
  console.error("Workspace Main 시작 실패", error);
  app.exit(1);
});
