import { Settings } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { usePuckBridge } from "@/hooks/usePuckBridge";

export function SettingsButton() {
  const { openSettings } = usePuckBridge();

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button type="button" variant="ghost" size="icon-sm" onClick={openSettings} aria-label="설정">
          <Settings className="size-4" />
        </Button>
      </TooltipTrigger>
      <TooltipContent>설정</TooltipContent>
    </Tooltip>
  );
}
