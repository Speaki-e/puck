import type { HydratePayload } from "./bridge-types";

/**
 * `pnpm dev` runs in a plain browser tab with no WKWebView/Swift on the
 * other end -- this feeds a canned state:hydrate so the UI is visible for
 * layout/style iteration without a full Xcode rebuild cycle each time.
 * Dev-only (import.meta.env.DEV), never bundled into the real dist/ build
 * that ships inside PuckClient.
 */
export function installDevMockBridge(): void {
  if (!import.meta.env.DEV || window.webkit?.messageHandlers?.puckChat) return;

  const hydrate: HydratePayload = {
    themeStyle: "dark",
    workspaces: [
      { id: "default", name: "일상 대화", projectPath: null, canOpenEditor: false },
      { id: "w2", name: "puck", projectPath: "/Users/byeolki/Documents/Project/Speaki-e/puck", canOpenEditor: true },
    ],
    activeWorkspaceId: "default",
    activeSessionId: "default",
    sessionsByWorkspace: {
      default: [
        { id: "default", workspaceId: "default", title: "일상 대화", isRunning: false },
        { id: "s2", workspaceId: "default", title: "다이내믹 아일랜드 제거", isRunning: false },
      ],
      w2: [{ id: "default", workspaceId: "w2", title: "일상 대화", isRunning: false }],
    },
    activeSession: {
      id: "default",
      workspaceId: "default",
      title: "일상 대화",
      isRunning: false,
      pendingApproval: null,
      timeline: [
        { kind: "userMessage", id: "1", text: "다이내믹 아일랜드 기능 및 관련 코드 전부 없애줘." },
        { kind: "assistantText", id: "2", text: "다이내믹 아일랜드(노치) 기능 제거하고 빌드·테스트까지 확인 완료했습니다." },
        { kind: "toolCall", id: "3", tool: "run_shell", args: { command: "rm -rf Puck/Notch PuckTests/Notch" } },
        { kind: "toolResult", id: "3", ok: true, data: { summary: "18 files removed" }, error: null, detail: null },
      ],
    },
    editorOpen: false,
  };

  window.webkit = {
    messageHandlers: {
      puckChat: {
        postMessage(body) {
          console.log("[dev-mock-bridge] action:", body);
          const message = body as { type: string };
          if (message.type === "action:ready") {
            setTimeout(() => window.PuckChatBridge?.receive({ type: "state:hydrate", payload: hydrate }), 0);
          }
        },
      },
    },
  };
}
