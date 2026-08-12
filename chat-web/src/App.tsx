import { useEffect } from "react";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Sidebar } from "@/components/sidebar/Sidebar";
import { TopBar } from "@/components/topbar/TopBar";
import { ChatTranscript } from "@/components/chat/ChatTranscript";
import { ChatInputBar } from "@/components/chat/ChatInputBar";
import { ApprovalBanner } from "@/components/chat/ApprovalBanner";
import { ChatProvider, useChatState } from "@/state/chat-context";
import { usePuckBridge } from "@/hooks/usePuckBridge";

const ASSISTANT_NAME = "Puck";

function ChatWindow() {
  const state = useChatState();
  const { ready, sendMessage, cancelRun, respondApproval } = usePuckBridge();

  useEffect(() => {
    ready();
  }, [ready]);

  return (
    <div className="flex h-screen w-screen bg-canvas text-foreground">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <TopBar />
        {state.activeSession ? (
          <>
            <ChatTranscript session={state.activeSession} assistantName={ASSISTANT_NAME} />
            <div className="px-4">
              {state.activeSession.pendingApproval && (
                <ApprovalBanner
                  approval={state.activeSession.pendingApproval}
                  onRespond={(approved) =>
                    respondApproval(state.activeWorkspaceId, state.activeSessionId, state.activeSession!.pendingApproval!.approvalId, approved)
                  }
                />
              )}
            </div>
            <ChatInputBar
              isRunning={state.activeSession.isRunning}
              onSend={(text) => sendMessage(state.activeWorkspaceId, state.activeSessionId, text)}
              onCancel={() => cancelRun(state.activeWorkspaceId, state.activeSessionId)}
            />
          </>
        ) : (
          <div className="flex-1" />
        )}
      </div>
    </div>
  );
}

export function App() {
  return (
    <ChatProvider>
      <TooltipProvider>
        <ChatWindow />
      </TooltipProvider>
    </ChatProvider>
  );
}
