import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./monaco";
import "./styles.css";
import { createGatewayTransport, parseGatewayWorkspaceId } from "./gateway-transport";
import { createGatewayWorkspaceApi } from "./gateway-workspace-api";

// 폴백 셸(Electron)에서는 preload가 이 시점 이전에 이미 window.workspace를 심어둔다(contextBridge).
// pet-app의 WKWebView처럼 preload가 없는 호스트에서만 EditorGateway용 WebSocket 구현으로 채운다
// (plan/03_workspace.md 4.1).
if (!window.workspace) {
  const workspaceId = parseGatewayWorkspaceId(location.pathname);
  const token = new URLSearchParams(location.search).get("token") ?? "";
  window.workspace = createGatewayWorkspaceApi(createGatewayTransport(workspaceId, token), workspaceId);
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
