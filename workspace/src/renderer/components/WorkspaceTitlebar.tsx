import type { WorkspaceApi } from "../workspace-api";
import { Icon } from "./Icon";
import { Badge } from "./ui/badge";
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
      <div className="brand-lockup">
        <span className="brand-mark" aria-hidden>
          <svg viewBox="0 0 24 24" fill="none">
            <circle cx="6" cy="7" r="2.25" />
            <circle cx="18" cy="7" r="2.25" />
            <circle cx="12" cy="17" r="2.25" />
            <path d="M8 8.2 10.8 15M16 8.2 13.2 15M8.2 7h7.6" />
          </svg>
        </span>
        <span className="brand-name">Workspace</span>
        <Badge variant="outline" className="alpha-badge">ALPHA</Badge>
      </div>
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
