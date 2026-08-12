import { useState } from "react";
import { FolderOpen } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { usePuckBridge } from "@/hooks/usePuckBridge";

interface NewWorkspaceDialogProps {
  open: boolean;
  onOpenChange(open: boolean): void;
}

export function NewWorkspaceDialog({ open, onOpenChange }: NewWorkspaceDialogProps) {
  const { newWorkspace, chooseProjectFolder } = usePuckBridge();
  const [name, setName] = useState("");
  const [projectPath, setProjectPath] = useState<string | null>(null);

  const reset = () => {
    setName("");
    setProjectPath(null);
  };

  const handlePickFolder = async () => {
    const path = await chooseProjectFolder();
    if (path) setProjectPath(path);
  };

  const handleCreate = () => {
    if (!name.trim()) return;
    newWorkspace(name.trim(), projectPath);
    reset();
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) reset(); onOpenChange(next); }}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>워크스페이스 추가</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new-workspace-name">이름</Label>
            <Input id="new-workspace-name" value={name} onChange={(event) => setName(event.target.value)} autoFocus />
          </div>
          <Button type="button" variant="outline" className="justify-start" onClick={() => void handlePickFolder()}>
            <FolderOpen className="size-4" />
            {projectPath ?? "프로젝트 폴더 없음 (순수 채팅)"}
          </Button>
        </div>
        <DialogFooter>
          <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>취소</Button>
          <Button type="button" disabled={!name.trim()} onClick={handleCreate}>추가</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
