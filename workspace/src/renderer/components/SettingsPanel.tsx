import { useEffect, useState } from "react";
import type { SettingsSnapshot, WorkspaceSettings } from "../../shared/settings-contract";
import type { WorkspaceApi } from "../workspace-api";
import { Button } from "./ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "./ui/dialog";
import { Input } from "./ui/input";
import { Label } from "./ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "./ui/select";
import { Slider } from "./ui/slider";

interface Props {
  api: WorkspaceApi;
  onClose(): void;
  onProjectSelected(projectPath: string): void;
}

const LOG_LEVELS: WorkspaceSettings["logLevel"][] = ["debug", "info", "warn", "error"];

function formatBytes(bytes: number): string {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function SettingsPanel({ api, onClose, onProjectSelected }: Props) {
  const [snapshot, setSnapshot] = useState<SettingsSnapshot>();
  const [apiKeyInput, setApiKeyInput] = useState("");
  const [status, setStatus] = useState("");

  useEffect(() => {
    void api.getSettings?.().then(setSnapshot);
  }, [api]);

  const handleOpenChange = (open: boolean) => {
    if (!open) onClose();
  };

  if (!snapshot) {
    return (
      <Dialog open onOpenChange={handleOpenChange}>
        <DialogContent showCloseButton={false} className="settings-panel" aria-label="설정">
          <p>불러오는 중…</p>
        </DialogContent>
      </Dialog>
    );
  }

  const update = async (patch: Partial<WorkspaceSettings>) => {
    if (!api.updateSettings) return;
    const next = await api.updateSettings(patch);
    setSnapshot(next);
  };

  const saveApiKey = async () => {
    if (!api.setApiKey || !apiKeyInput.trim()) return;
    await api.setApiKey(apiKeyInput.trim());
    setApiKeyInput("");
    setStatus("API 키를 저장했습니다. Agent Host 재시작 후 반영됩니다.");
    const next = await api.getSettings?.();
    if (next) setSnapshot(next);
  };

  const clearApiKey = async () => {
    if (!api.clearApiKey) return;
    await api.clearApiKey();
    setStatus("API 키를 삭제했습니다.");
    const next = await api.getSettings?.();
    if (next) setSnapshot(next);
  };

  return (
    <Dialog open onOpenChange={handleOpenChange}>
      <DialogContent showCloseButton={false} className="settings-panel" aria-label="설정">
        <DialogHeader>
          <div className="flex items-center justify-between">
            <DialogTitle>설정</DialogTitle>
            <Button type="button" variant="ghost" size="icon-sm" onClick={onClose} aria-label="설정 닫기">×</Button>
          </div>
        </DialogHeader>

        <section>
          <h3>API 키</h3>
          <p className="settings-hint">{snapshot.hasApiKey ? "Claude API 키가 설정돼 있습니다." : "Claude API 키가 설정되지 않았습니다."}</p>
          <div className="settings-row">
            <Input
              type="password"
              value={apiKeyInput}
              onChange={(event) => setApiKeyInput(event.target.value)}
              placeholder="sk-ant-..."
              aria-label="Claude API 키"
            />
            <Button type="button" onClick={() => void saveApiKey()} disabled={!apiKeyInput.trim()}>저장</Button>
            {snapshot.hasApiKey && <Button type="button" variant="ghost" onClick={() => void clearApiKey()}>삭제</Button>}
          </div>
          {status && <p className="settings-hint">{status}</p>}
        </section>

        <section>
          <h3>모델</h3>
          <Label htmlFor="settings-model" className="sr-only">모델</Label>
          <Input
            id="settings-model"
            value={snapshot.model}
            onChange={(event) => setSnapshot({ ...snapshot, model: event.target.value })}
            onBlur={() => void update({ model: snapshot.model })}
            aria-label="모델"
          />
        </section>

        <section>
          <h3>파일 크기 제한</h3>
          <div className="settings-row">
            <Slider
              min={1}
              max={20}
              value={[Math.round(snapshot.fileSizeLimitBytes / (1024 * 1024))]}
              onValueChange={([next]) => setSnapshot({ ...snapshot, fileSizeLimitBytes: next * 1024 * 1024 })}
              onValueCommit={() => void update({ fileSizeLimitBytes: snapshot.fileSizeLimitBytes })}
              aria-label="편집 가능 파일 크기 제한"
            />
            <span>{formatBytes(snapshot.fileSizeLimitBytes)}</span>
          </div>
        </section>

        <section>
          <h3>로그 수준</h3>
          <Label htmlFor="settings-log-level" className="sr-only">로그 수준</Label>
          <Select
            value={snapshot.logLevel}
            onValueChange={(next) => void update({ logLevel: next as WorkspaceSettings["logLevel"] })}
          >
            <SelectTrigger id="settings-log-level" aria-label="로그 수준" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {LOG_LEVELS.map((level) => <SelectItem key={level} value={level}>{level}</SelectItem>)}
            </SelectContent>
          </Select>
        </section>

        {snapshot.windowSize && (
          <section>
            <h3>창 크기</h3>
            <p className="settings-hint">{snapshot.windowSize.width} × {snapshot.windowSize.height} (이동·크기 조절 시 자동 저장됨)</p>
          </section>
        )}

        <section>
          <h3>최근 프로젝트</h3>
          {snapshot.recentProjects.length === 0 ? (
            <p className="settings-hint">아직 연 프로젝트가 없습니다.</p>
          ) : (
            <ul className="recent-projects">
              {snapshot.recentProjects.map((project) => (
                <li key={project.id}>
                  <Button type="button" variant="ghost" onClick={() => onProjectSelected(project.projectPath)}>
                    <strong>{project.name}</strong>
                    <span>{project.projectPath}</span>
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </section>
      </DialogContent>
    </Dialog>
  );
}
