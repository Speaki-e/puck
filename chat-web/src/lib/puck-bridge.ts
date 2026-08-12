import type { BridgeInboundMessage, BridgeOutboundMessage } from "./bridge-types";

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        puckChat?: { postMessage(body: unknown): void };
      };
    };
    PuckChatBridge?: {
      receive(message: BridgeInboundMessage): void;
    };
  }
}

type Listener = (message: BridgeInboundMessage) => void;

const listeners = new Set<Listener>();

/**
 * Swift calls window.PuckChatBridge.receive(...) via evaluateJavaScript --
 * this registers that entry point once, at module load, so it's guaranteed
 * to exist before Swift's first push (ClientChatBridge.swift only starts
 * pushing after action:ready, but registering eagerly here removes any
 * ordering assumption on the Swift side).
 */
window.PuckChatBridge = {
  receive(message) {
    for (const listener of listeners) listener(message);
  },
};

export function subscribeToBridge(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/**
 * No-op with a console warning outside a real WKWebView host (e.g. `pnpm
 * dev` in a plain browser tab) -- lets the app run for visual iteration
 * without a live Swift side, same idea as workspace's fallback-vs-gateway
 * detection in main.tsx.
 */
export function sendToBridge(message: BridgeOutboundMessage): void {
  const handler = window.webkit?.messageHandlers?.puckChat;
  if (!handler) {
    console.warn("[puck-bridge] no native handler -- running outside PuckClient?", message);
    return;
  }
  handler.postMessage(message);
}
