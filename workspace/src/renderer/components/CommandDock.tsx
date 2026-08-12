import { Icon } from "./Icon";
import { Button } from "./ui/button";
import { Input } from "./ui/input";

interface CommandDockProps {
  status: string;
  command: string;
  enabled: boolean;
  onCommandChange(value: string): void;
  onRun(): void;
  onCancel(): void;
}

export function CommandDock({
  status,
  command,
  enabled,
  onCommandChange,
  onRun,
  onCancel,
}: CommandDockProps) {
  return (
    <footer className="command-dock">
      <div className="status-block">
        <span className="status-pulse" />
        <div>
          <span className="eyebrow">STATUS</span>
          <span className="status-text" aria-label="현재 상태">{status}</span>
        </div>
      </div>
      <div className="command-composer">
        <span className="composer-icon"><Icon name="sparkle" /></span>
        <Input
          value={command}
          onChange={(event) => onCommandChange(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Enter") onRun(); }}
          placeholder={enabled ? "Agent에게 코드 작업을 요청하세요…" : "먼저 프로젝트를 열어주세요"}
          aria-label="에이전트 명령"
          disabled={!enabled}
        />
        <span className="enter-hint">ENTER</span>
        <Button
          type="button"
          className="run-button"
          onClick={onRun}
          disabled={!enabled || !command.trim()}
          aria-label="명령 실행"
        >
          <Icon name="play" />
        </Button>
      </div>
      <Button type="button" variant="outline" className="stop-button" onClick={onCancel}>
        <Icon name="stop" /> 중지
      </Button>
    </footer>
  );
}
