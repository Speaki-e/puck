import type { EditorTab } from "../editor-state";
import { isDirty } from "../editor-state";

interface Props {
  tabs: EditorTab[];
  activePath?: string;
  onActivate(path: string): void;
  onClose(path: string): void;
}

export function EditorTabs({ tabs, activePath, onActivate, onClose }: Props) {
  return (
    <div className="tab-strip" role="tablist">
      {tabs.map((tab) => (
        <button
          type="button"
          role="tab"
          aria-selected={tab.path === activePath}
          className={`editor-tab ${tab.path === activePath ? "active" : ""}`}
          key={tab.path}
          onClick={() => onActivate(tab.path)}
          title={tab.path}
        >
          <span>{tab.path.split("/").at(-1)}</span>
          {isDirty(tab) && <span className="dirty-dot">●</span>}
          <span
            className="tab-close"
            role="button"
            tabIndex={0}
            onClick={(event) => { event.stopPropagation(); onClose(tab.path); }}
            onKeyDown={(event) => { if (event.key === "Enter") onClose(tab.path); }}
          >×</span>
        </button>
      ))}
    </div>
  );
}
