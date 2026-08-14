import { useState } from "react";
import { Check, Folder, MessageSquareText, Plus } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import type { WorkspaceJSON } from "@/lib/bridge-types";
import { NewWorkspaceDialog } from "./NewWorkspaceDialog";

interface WorkspaceSwitcherProps {
  workspaces: WorkspaceJSON[];
  activeWorkspaceId: string;
  expanded: boolean;
  onSelect(workspaceId: string): void;
}

export function WorkspaceSwitcher({ workspaces, activeWorkspaceId, expanded, onSelect }: WorkspaceSwitcherProps) {
  const [open, setOpen] = useState(false);
  const [showNewWorkspace, setShowNewWorkspace] = useState(false);
  const activeWorkspace = workspaces.find((workspace) => workspace.id === activeWorkspaceId);

  return (
    <>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button type="button" variant="ghost" className={cn("h-auto justify-start gap-2 px-1.5 py-1.5", !expanded && "w-full justify-center px-0")}>
            <Avatar className="size-6 shrink-0">
              <AvatarFallback className="bg-brand text-[11px] font-medium text-on-brand">
                {(activeWorkspace?.name ?? "?").slice(0, 1).toUpperCase()}
              </AvatarFallback>
            </Avatar>
            {expanded && <span className="truncate text-sm font-medium">{activeWorkspace?.name ?? ""}</span>}
          </Button>
        </PopoverTrigger>
        <PopoverContent align="start" className="w-64 p-1">
          <div className="flex flex-col gap-0.5">
            {workspaces.map((workspace) => (
              <button
                key={workspace.id}
                type="button"
                onClick={() => { onSelect(workspace.id); setOpen(false); }}
                className="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-hairline-soft"
              >
                {workspace.projectPath ? <Folder className="size-3.5 shrink-0 text-mute" /> : <MessageSquareText className="size-3.5 shrink-0 text-mute" />}
                <span className="min-w-0 flex-1 truncate">{workspace.name}</span>
                {workspace.id === activeWorkspaceId && <Check className="size-3.5 shrink-0 text-brand" />}
              </button>
            ))}
          </div>
          <div className="mt-1 border-t border-hairline pt-1">
            <button
              type="button"
              onClick={() => { setOpen(false); setShowNewWorkspace(true); }}
              className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-muted-foreground hover:bg-hairline-soft"
            >
              <Plus className="size-3.5 shrink-0" />
              워크스페이스 추가
            </button>
          </div>
        </PopoverContent>
      </Popover>
      <NewWorkspaceDialog open={showNewWorkspace} onOpenChange={setShowNewWorkspace} />
    </>
  );
}
