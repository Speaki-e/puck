import type { EditorTab } from "../editor-state";
import { isDirty } from "../editor-state";
import { Button } from "./ui/button";

interface Props {
  tabs: EditorTab[];
  activePath?: string;
  onActivate(path: string): void;
  onClose(path: string): void;
}

export function EditorTabs({ tabs, activePath, onActivate, onClose }: Props) {
  return (
    <div className="tab-strip" role="tablist" aria-label="열린 파일">
      <div className="window-controls" aria-hidden><i /><i /><i /></div>
      <div className="tabs-scroll">
        {tabs.map((tab) => {
          const active = tab.path === activePath;
          const extension = tab.path.split(".").at(-1)?.toUpperCase().slice(0, 2) ?? "·";
          return (
            <div className={`editor-tab ${active ? "active" : ""}`} key={tab.path} role="presentation">
              <button type="button" role="tab" aria-selected={active} className="tab-main" onClick={() => onActivate(tab.path)} title={tab.path}>
                <span className="tab-file-icon">{extension}</span>
                <span className="tab-name">{tab.path.split("/").at(-1)}</span>
                {isDirty(tab) && <span className="dirty-dot" title="저장하지 않은 변경" />}
              </button>
              <Button type="button" variant="ghost" size="icon-sm" className="tab-close" onClick={() => onClose(tab.path)} aria-label={`${tab.path} 닫기`}>×</Button>
            </div>
          );
        })}
      </div>
      <span className="tab-strip-fill" />
    </div>
  );
}
