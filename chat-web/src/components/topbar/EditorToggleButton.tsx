import { CodeXml } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { useChatState } from "@/state/chat-context";
import { usePuckBridge } from "@/hooks/usePuckBridge";

export function EditorToggleButton() {
  const state = useChatState();
  const { toggleEditor } = usePuckBridge();

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          disabled={!state.editorCanOpen}
          onClick={toggleEditor}
          aria-label="에디터"
          aria-pressed={state.editorOpen}
          className={cn(!state.editorCanOpen && "opacity-40")}
        >
          <CodeXml className={cn("size-4", state.editorOpen && "text-brand")} />
        </Button>
      </TooltipTrigger>
      <TooltipContent>
        {state.editorCanOpen ? "에디터" : "이 워크스페이스에는 연결된 프로젝트가 없어요"}
      </TooltipContent>
    </Tooltip>
  );
}
