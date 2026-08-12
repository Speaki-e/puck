import { useCallback, useMemo } from "react";
import { subscribeToBridge, sendToBridge } from "../lib/puck-bridge";
import { useChatDispatch } from "../state/chat-context";

/**
 * Action senders for components -- thin wrappers over sendToBridge so call
 * sites read as verbs (`sendMessage(...)`) instead of raw envelope literals.
 * State updates always arrive back through the bridge subscription
 * (ChatProvider), never as a return value here -- Swift owns the real state
 * and this hook doesn't assume request/response pairing except for
 * chooseProjectFolder, which genuinely needs one (a native NSOpenPanel
 * result has nowhere else to go).
 */
export function usePuckBridge() {
  const dispatch = useChatDispatch();

  const ready = useCallback(() => {
    sendToBridge({ type: "action:ready", payload: {} });
  }, []);

  const sendMessage = useCallback((workspaceId: string, sessionId: string, text: string) => {
    const id = crypto.randomUUID();
    dispatch({ type: "local:optimisticUserMessage", payload: { workspaceId, sessionId, id, text } });
    sendToBridge({ type: "action:sendMessage", payload: { workspaceId, sessionId, text } });
  }, [dispatch]);

  const newSession = useCallback((workspaceId: string, title: string) => {
    sendToBridge({ type: "action:newSession", payload: { workspaceId, title } });
  }, []);

  const newWorkspace = useCallback((name: string, projectPath: string | null) => {
    sendToBridge({ type: "action:newWorkspace", payload: { name, projectPath } });
  }, []);

  const chooseProjectFolder = useCallback((): Promise<string | null> => {
    return new Promise((resolve) => {
      const unsubscribe = subscribeToBridge((message) => {
        if (message.type !== "state:projectFolderChosen") return;
        unsubscribe();
        resolve(message.payload.path);
      });
      sendToBridge({ type: "action:chooseProjectFolder", payload: {} });
    });
  }, []);

  const switchWorkspace = useCallback((workspaceId: string) => {
    sendToBridge({ type: "action:switchWorkspace", payload: { workspaceId } });
  }, []);

  const switchSession = useCallback((workspaceId: string, sessionId: string) => {
    sendToBridge({ type: "action:switchSession", payload: { workspaceId, sessionId } });
  }, []);

  const respondApproval = useCallback((workspaceId: string, sessionId: string, approvalId: string, approved: boolean) => {
    sendToBridge({ type: "action:respondApproval", payload: { workspaceId, sessionId, approvalId, approved } });
  }, []);

  const cancelRun = useCallback((workspaceId: string, sessionId: string) => {
    sendToBridge({ type: "action:cancelRun", payload: { workspaceId, sessionId } });
  }, []);

  const toggleEditor = useCallback(() => {
    sendToBridge({ type: "action:toggleEditor", payload: {} });
  }, []);

  const openSettings = useCallback(() => {
    sendToBridge({ type: "action:openSettings", payload: {} });
  }, []);

  return useMemo(
    () => ({
      ready,
      sendMessage,
      newSession,
      newWorkspace,
      chooseProjectFolder,
      switchWorkspace,
      switchSession,
      respondApproval,
      cancelRun,
      toggleEditor,
      openSettings,
    }),
    [ready, sendMessage, newSession, newWorkspace, chooseProjectFolder, switchWorkspace, switchSession, respondApproval, cancelRun, toggleEditor, openSettings],
  );
}
