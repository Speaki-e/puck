import type { JSONValue } from "@speaki-e/protocol";

export interface EditorMessage {
  requestId?: string;
  workspaceId: string;
  type: string;
  payload: JSONValue;
}

export interface EditorTransport {
  request<T extends JSONValue = JSONValue>(message: EditorMessage): Promise<T>;
  subscribe(listener: (message: EditorMessage) => void): () => void;
}
