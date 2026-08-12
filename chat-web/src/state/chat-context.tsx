import { createContext, useContext, useEffect, useReducer, type ReactNode } from "react";
import { subscribeToBridge } from "../lib/puck-bridge";
import { chatReducer, initialChatState, type ChatAction, type ChatState } from "./chat-reducer";

const ChatStateContext = createContext<ChatState | null>(null);
const ChatDispatchContext = createContext<((action: ChatAction) => void) | null>(null);

export function ChatProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(chatReducer, initialChatState);

  useEffect(() => subscribeToBridge(dispatch), []);

  return (
    <ChatStateContext.Provider value={state}>
      <ChatDispatchContext.Provider value={dispatch}>{children}</ChatDispatchContext.Provider>
    </ChatStateContext.Provider>
  );
}

export function useChatState(): ChatState {
  const state = useContext(ChatStateContext);
  if (!state) throw new Error("useChatState must be used within ChatProvider");
  return state;
}

export function useChatDispatch(): (action: ChatAction) => void {
  const dispatch = useContext(ChatDispatchContext);
  if (!dispatch) throw new Error("useChatDispatch must be used within ChatProvider");
  return dispatch;
}
