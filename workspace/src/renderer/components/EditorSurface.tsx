import Editor, { DiffEditor } from "@monaco-editor/react";
import type { EditorTab } from "../editor-state";
import { isDirty } from "../editor-state";
import { configureMonaco, MONACO_FONT_FAMILY } from "../monaco-config";
import { Icon } from "./Icon";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";

interface EditorSurfaceProps {
  active?: EditorTab;
  diffAgainstDisk?: string;
  onEdit(content: string): void;
  onSave(): void;
  onToggleDiff(): void;
  onReload(): void;
  onKeepMine(): void;
  onOpenProject(): void;
}

export function EditorSurface({
  active,
  diffAgainstDisk,
  onEdit,
  onSave,
  onToggleDiff,
  onReload,
  onKeepMine,
  onOpenProject,
}: EditorSurfaceProps) {
  const breadcrumbs = active?.path.split("/") ?? [];

  return (
    <>
      <div className="editor-toolbar">
        <nav className="breadcrumbs" aria-label="현재 파일 경로">
          {breadcrumbs.length ? breadcrumbs.map((part, index) => (
            <span key={`${part}-${index}`} className={index === breadcrumbs.length - 1 ? "current" : ""}>
              {part}{index < breadcrumbs.length - 1 && <b>/</b>}
            </span>
          )) : <span className="muted">파일을 선택하세요</span>}
        </nav>
        {active && <Badge variant="outline" className="language-badge">{active.language}</Badge>}
        {active?.readOnly && <Badge variant="outline" className="readonly-badge">READ ONLY</Badge>}
        <Button
          type="button"
          variant="ghost"
          className="save-button"
          onClick={onSave}
          disabled={!active || active.readOnly || !isDirty(active)}
          title="저장 (Ctrl/Cmd + S)"
        >
          <Icon name="save" /> 저장
        </Button>
      </div>

      <div className="editor-stage">
        {active ? (
          <>
            {active.diskChanged && (
              <div className="conflict-banner" role="alert">
                <div className="conflict-symbol">!</div>
                <div className="conflict-copy">
                  <strong>디스크에서 파일이 변경됐습니다</strong>
                  <span>저장하기 전에 사용할 버전을 선택하세요.</span>
                </div>
                {!active.previewUrl && (
                  <Button type="button" variant="ghost" onClick={onToggleDiff}>
                    {diffAgainstDisk === undefined ? "diff 비교" : "diff 닫기"}
                  </Button>
                )}
                <Button type="button" variant="ghost" onClick={onReload}>디스크 내용 사용</Button>
                <Button type="button" onClick={onKeepMine}>내 내용 유지</Button>
              </div>
            )}
            {active.previewUrl ? (
              <div className="image-preview">
                <div className="image-preview-canvas">
                  <img src={active.previewUrl} alt={active.path.split("/").at(-1)} />
                </div>
                <div className="image-metadata">
                  <strong>{active.path.split("/").at(-1)}</strong>
                  <span>{active.mimeType}</span>
                  <span>{Math.max(1, Math.round(active.size / 1024))} KB</span>
                </div>
              </div>
            ) : diffAgainstDisk !== undefined ? (
              <DiffEditor
                original={diffAgainstDisk}
                modified={active.content}
                language={active.language}
                theme="workspace-dark"
                beforeMount={configureMonaco}
                options={{
                  readOnly: true,
                  renderSideBySide: true,
                  automaticLayout: true,
                  fontFamily: MONACO_FONT_FAMILY,
                  fontSize: 13,
                }}
              />
            ) : (
              <Editor
                path={active.path}
                value={active.content}
                language={active.language}
                theme="workspace-dark"
                beforeMount={configureMonaco}
                onChange={(value) => onEdit(value ?? "")}
                options={{
                  readOnly: active.readOnly,
                  automaticLayout: true,
                  minimap: { enabled: true, renderCharacters: false, maxColumn: 90, scale: 0.8 },
                  fontFamily: MONACO_FONT_FAMILY,
                  fontSize: 13,
                  lineHeight: 21,
                  fontLigatures: true,
                  padding: { top: 20, bottom: 20 },
                  scrollBeyondLastLine: false,
                  smoothScrolling: true,
                  cursorSmoothCaretAnimation: "on",
                  bracketPairColorization: { enabled: true },
                  guides: { bracketPairs: true, indentation: true },
                  renderLineHighlight: "all",
                  overviewRulerBorder: false,
                }}
              />
            )}
          </>
        ) : (
          <div className="empty-editor">
            <span className="eyebrow">LIGHTWEIGHT CODE WORKSPACE</span>
            <h1>프로젝트를 열고,<br />아이디어를 코드로 만드세요.</h1>
            <p>왼쪽 탐색기에서 파일을 선택하거나 Agent에게<br />원하는 변경을 자연어로 요청할 수 있습니다.</p>
            <div className="empty-actions">
              <Button type="button" className="button-primary" onClick={onOpenProject}>
                <Icon name="folder" /> 프로젝트 열기
              </Button>
              <span><kbd>Ctrl</kbd><b>+</b><kbd>S</kbd> 빠른 저장</span>
            </div>
          </div>
        )}
      </div>
    </>
  );
}
