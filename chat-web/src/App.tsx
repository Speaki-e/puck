import { useEffect } from "react";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Sidebar } from "@/components/sidebar/Sidebar";
import { TabStrip } from "@/components/topbar/TabStrip";
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
        <div className="h-7 shrink-0" /> {/* clears the native titlebar traffic lights -- see Sidebar.tsx's spacer */}
        <TabStrip />
        {state.activeSession ? (
          <>
            <ChatTranscript
              session={state.activeSession}
              assistantName={ASSISTANT_NAME}
              projectPath={state.workspaces.find((workspace) => workspace.id === state.activeSession!.workspaceId)?.projectPath ?? null}
            />
            <div className="px-4">
              {state.activeSession.pendingApproval && (
                <ApprovalBanner
                  approval={state.activeSession.pendingApproval}
                  onRespond={(approved) =>
                    respondApproval(state.activeSession!.workspaceId, state.activeSession!.id, state.activeSession!.pendingApproval!.approvalId, approved)
                  }
                />
              )}
            </div>
            <ChatInputBar
              isRunning={state.activeSession.isRunning}
              onSend={(text) => sendMessage(state.activeSession!.workspaceId, state.activeSession!.id, text)}
              onCancel={() => cancelRun(state.activeSession!.workspaceId, state.activeSession!.id)}
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
