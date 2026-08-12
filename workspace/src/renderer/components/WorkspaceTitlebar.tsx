import type { WorkspaceApi } from "../workspace-api";
import { Icon } from "./Icon";
import { Button } from "./ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";

interface WorkspaceTitlebarProps {
  api?: WorkspaceApi;
  title: string;
  projectPath?: string;
  connected: boolean;
  onOpenProject(): void;
  onOpenSettings(): void;
}

export function WorkspaceTitlebar({
  api,
  title,
  projectPath,
  connected,
  onOpenProject,
  onOpenSettings,
}: WorkspaceTitlebarProps) {
  return (
    <header className="titlebar">
      <div className="project-identity" title={projectPath}>
        <span className={`project-dot ${connected ? "connected" : ""}`} />
        <strong>{title}</strong>
        <span className="project-path">{projectPath ?? "프로젝트가 연결되지 않음"}</span>
      </div>
      <div className="titlebar-actions">
        <Button type="button" variant="ghost" className="project-button" onClick={onOpenProject}>
          <Icon name="folder" /> 프로젝트 열기
        </Button>
        {api?.getSettings && (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button type="button" variant="ghost" size="icon" onClick={onOpenSettings} aria-label="설정">
                <Icon name="gear" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>설정</TooltipContent>
          </Tooltip>
        )}
        {api?.platform === "win32" && (
          <div className="window-actions" aria-label="창 제어">
            <button type="button" onClick={() => void api.windowControl("minimize")} aria-label="창 최소화"><span className="minimize-symbol" /></button>
            <button type="button" onClick={() => void api.windowControl("maximize")} aria-label="창 최대화"><span className="maximize-symbol" /></button>
            <button type="button" className="window-close" onClick={() => void api.windowControl("close")} aria-label="창 닫기"><span className="close-symbol" /></button>
          </div>
        )}
      </div>
    </header>
  );
}
